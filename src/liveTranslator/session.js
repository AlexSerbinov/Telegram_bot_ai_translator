/**
 * LiveTranslatorSession — full speech-to-speech orchestrator for one client connection.
 *
 * Wires together:
 *   SonioxSession (STT)  →  trigger policy  →  Groq translator  →  ElevenSession (TTS)
 *
 * Owns all per-session state (accumulated source, committed translation, inFlight guard,
 * auto-speed loop). Caller (the WS route) feeds it client audio and listens for events.
 *
 * Events emitted:
 *   'src_partial'  ({ text })                                     — interim STT
 *   'src_final'    ({ text })                                     — finalized & script-filtered STT chunk
 *   'tgt_chunk'    ({ text, mode, transMs, dropReason? })        — committed translation chunk
 *   'tts_audio'    (Buffer pcm s16le 24 kHz)                      — synthesized PCM frame
 *   'tts_first_byte' ({ latencyMs })                              — first audio byte of a chunk
 *   'metrics'      ({ queueSec, secondsBehind, currentSpeed, mode, srcCharsLeft })
 *   'log'          ({ level, msg })                               — diagnostics
 *   'error'        ({ message, stage })                           — fatal problem
 *   'finished'                                                     — graceful shutdown done
 */
const EventEmitter = require('events');
const { filterToScript } = require('./scriptFilter');
const { decide } = require('./triggerPolicy');
const { translateIncremental } = require('./translator');
const { ElevenSession } = require('./ttsEleven');
const { SonioxTtsSession } = require('./ttsSoniox');
const { SonioxSession } = require('./sttSoniox');
const autoSpeed = require('./autoSpeed');

const TICK_MS = 250;
const CONTEXT_CHARS = 240;
const PUNCT_TAIL_RE = /[.,!?;:…»"”')]\s*$/;

class LiveTranslatorSession extends EventEmitter {
  constructor({
    groqApiKey,
    sonioxApiKey,        // STT key
    sonioxTtsApiKey,     // TTS key (may equal STT key)
    sonioxTtsVoice = 'Maya',
    elevenApiKey,
    elevenVoiceId,
    defaultTtsProvider = 'soniox',
  }) {
    super();
    this.groqApiKey       = groqApiKey;
    this.sonioxApiKey     = sonioxApiKey;
    this.sonioxTtsApiKey  = sonioxTtsApiKey || sonioxApiKey;
    this.sonioxTtsVoice   = sonioxTtsVoice;
    this.elevenApiKey     = elevenApiKey;
    this.elevenVoiceId    = elevenVoiceId;
    this.defaultTtsProvider = defaultTtsProvider;
    this.ttsProvider      = defaultTtsProvider;

    // Pipeline state
    this.sourceLang = 'es';
    this.targetLang = 'uk';
    this.accumulatedFinal = '';
    this.lastInterim = '';
    this.committedSrcLen = 0;
    this.committedTrans = '';
    this.inFlight = false;

    // Speed control
    this.voiceSpeed = 1.0;        // current speed (LERP'd toward target when auto)
    this.autoSpeedOn = false;
    this.clientQueueSec = 0;

    // Upstreams
    this.stt = null;
    this.tts = null;
    this.tickHandle = null;
    this.running = false;
  }

  async start({ sourceLang = 'es', targetLang = 'uk', voiceSpeed = 1.0, autoSpeedOn = false, ttsProvider } = {}) {
    if (sourceLang === targetLang) throw new Error('source and target must differ');
    this.sourceLang = sourceLang;
    this.targetLang = targetLang;
    this.voiceSpeed = clamp01(voiceSpeed);
    this.autoSpeedOn = !!autoSpeedOn;
    this.ttsProvider = (ttsProvider === 'eleven' || ttsProvider === 'soniox')
      ? ttsProvider
      : this.defaultTtsProvider;
    this.accumulatedFinal = '';
    this.lastInterim = '';
    this.committedSrcLen = 0;
    this.committedTrans = '';
    this.inFlight = false;
    this.clientQueueSec = 0;

    this._log('info', `start ${sourceLang}→${targetLang} tts=${this.ttsProvider} speed=${this.voiceSpeed} auto=${this.autoSpeedOn}`);

    // STT upstream
    this.stt = new SonioxSession({ apiKey: this.sonioxApiKey, sourceLang });
    this.stt.on('partial', (text) => {
      const cleaned = filterToScript(text, this.sourceLang);
      this.lastInterim = cleaned;
      this.emit('src_partial', { text: cleaned });
    });
    this.stt.on('final', (text) => {
      const cleaned = filterToScript(text, this.sourceLang);
      if (text && !cleaned.trim()) {
        this._log('debug', `[script-skip] dropped final "${text.trim()}"`);
        return;
      }
      this.accumulatedFinal += cleaned;
      this.emit('src_final', { text: cleaned });
      // Aggressive trigger on punctuation
      if (PUNCT_TAIL_RE.test(cleaned)) this._tick();
    });
    this.stt.on('error', (e) => this._log('error', `[stt] ${e.message}`));
    this.stt.on('closed', () => this._log('info', '[stt] upstream closed'));
    await this.stt.open();

    // TTS upstream — provider-switchable
    this.tts = this._buildTts(targetLang);
    this.tts.on('audio', (buf) => this.emit('tts_audio', buf));
    this.tts.on('first-byte', (m) => this.emit('tts_first_byte', m));
    this.tts.on('error', (e) => this._log('error', `[tts:${this.ttsProvider}] ${e.message}`));
    this.tts.on('closed', () => this._log('info', `[tts:${this.ttsProvider}] upstream closed`));
    await this.tts.open();

    this.running = true;
    this.tickHandle = setInterval(() => this._periodic(), TICK_MS);
  }

  feedAudio(pcm) {
    if (!this.running || !this.stt) return;
    this.stt.feed(pcm);
  }

  reportClientQueue(queueSec) {
    if (Number.isFinite(queueSec)) this.clientQueueSec = Math.max(0, queueSec);
  }

  setSpeed(value) {
    if (!Number.isFinite(value)) return;
    this.voiceSpeed = clamp01(value);
    if (this.tts) this.tts.setSpeed(this.voiceSpeed);
  }

  setAuto(enabled) {
    this.autoSpeedOn = !!enabled;
  }

  async stop() {
    this.running = false;
    if (this.tickHandle) { clearInterval(this.tickHandle); this.tickHandle = null; }

    // Final flush of any remaining tail
    const pending = this.accumulatedFinal.slice(this.committedSrcLen).trim();
    if (pending) {
      try { await this._fireTranslate(pending, this.accumulatedFinal.length); } catch {}
    }

    if (this.stt) { this.stt.close(); this.stt = null; }
    if (this.tts) { this.tts.close(); this.tts = null; }
    this.emit('finished');
  }

  // ===== internals =====

  _buildTts(targetLang) {
    if (this.ttsProvider === 'soniox') {
      return new SonioxTtsSession({
        apiKey:   this.sonioxTtsApiKey,
        voice:    this.sonioxTtsVoice,
        language: targetLang,
      });
    }
    return new ElevenSession({
      apiKey:     this.elevenApiKey,
      voiceId:    this.elevenVoiceId,
      language:   targetLang,
      voiceSpeed: this.voiceSpeed,
    });
  }

  _periodic() {
    if (!this.running) return;
    this._tick();
    this._autoSpeedStep();
    this._emitMetrics();
  }

  _tick() {
    if (!this.running || this.inFlight) return;
    const pending = this.accumulatedFinal.slice(this.committedSrcLen).trim();
    if (!pending) return;
    const queueSec = this.clientQueueSec;
    const { fire, mode } = decide(pending, queueSec);
    if (!fire) return;
    const snapLen = this.accumulatedFinal.length;
    this._fireTranslate(pending, snapLen, mode).catch(e =>
      this._log('error', `[translate] ${e.message}`)
    );
  }

  async _fireTranslate(newSrc, snapLen, mode = 'unknown') {
    this.inFlight = true;
    try {
      const committedSrcText = this.accumulatedFinal.slice(0, this.committedSrcLen);
      const contextSrc = committedSrcText.slice(-CONTEXT_CHARS);
      const contextTrans = this.committedTrans.slice(-CONTEXT_CHARS);

      const result = await translateIncremental({
        apiKey: this.groqApiKey,
        text: newSrc,
        sourceLang: this.sourceLang,
        targetLang: this.targetLang,
        contextSrc,
        contextTrans,
      });

      if (result.dropReason) {
        this._log('warn', `[guard] dropped (${result.dropReason}) for "${newSrc.slice(0, 60)}"`);
        this.emit('tgt_chunk', { text: '', mode, transMs: result.elapsedMs, dropReason: result.dropReason });
        return;
      }

      // Advance committed index by snapshot length, append translation, send to TTS.
      this.committedSrcLen = Math.max(this.committedSrcLen, snapLen);
      this.committedTrans = (this.committedTrans ? this.committedTrans + ' ' : '') + result.translation;
      this.emit('tgt_chunk', { text: result.translation, mode, transMs: result.elapsedMs });
      if (this.tts) this.tts.chunk(result.translation);
    } finally {
      this.inFlight = false;
    }
  }

  _autoSpeedStep() {
    if (!this.autoSpeedOn) return;
    const srcCharsLeft = Math.max(0, this.accumulatedFinal.length - this.committedSrcLen);
    const sb = autoSpeed.secondsBehind(this.clientQueueSec, srcCharsLeft);
    const target = autoSpeed.targetSpeedFor(sb);
    const next = autoSpeed.lerp(this.voiceSpeed, target);
    const clamped = autoSpeed.clamp(next);
    if (Math.abs(clamped - this.voiceSpeed) >= 0.005) {
      this.voiceSpeed = clamped;
      if (this.tts) this.tts.setSpeed(this.voiceSpeed);
    }
  }

  _emitMetrics() {
    const srcCharsLeft = Math.max(0, this.accumulatedFinal.length - this.committedSrcLen);
    const sb = autoSpeed.secondsBehind(this.clientQueueSec, srcCharsLeft);
    const pending = this.accumulatedFinal.slice(this.committedSrcLen).trim();
    const { mode } = decide(pending, this.clientQueueSec);
    this.emit('metrics', {
      queueSec: this.clientQueueSec,
      secondsBehind: Number(sb.toFixed(2)),
      currentSpeed: Number(this.voiceSpeed.toFixed(3)),
      mode,
      srcCharsLeft,
    });
  }

  _log(level, msg) {
    this.emit('log', { level, msg });
  }
}

function clamp01(v) {
  if (!Number.isFinite(v)) return 1.0;
  return Math.max(0.7, Math.min(2.0, v));
}

module.exports = { LiveTranslatorSession };
