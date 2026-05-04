/**
 * Persistent ElevenLabs Flash v2.5 WebSocket session for streaming TTS.
 *
 * Wraps a single upstream connection per logical translator session. Caller does:
 *   const tts = new ElevenSession({ apiKey, voiceId, language, voiceSpeed });
 *   await tts.open();
 *   tts.chunk('Привіт');         // sends { text:'Привіт ', flush:true }
 *   tts.chunk('як справи');
 *   tts.setSpeed(1.15);          // applies on the NEXT chunk
 *   tts.close();
 *
 * Events:
 *   'audio'        (Buffer)            — PCM s16le 24 kHz mono frame
 *   'first-byte'   ({ latencyMs })     — first byte after a chunk(); resets per chunk
 *   'error'        ({ message })       — upstream error
 *   'closed'                           — upstream WS closed
 *
 * Server-side speed is clamped to ElevenLabs Flash v2.5 cap [0.7, 1.2]; anything
 * above is the client's job (playbackRate).
 */
const EventEmitter = require('events');
const WebSocket = require('ws');

const SPEED_MIN = 0.7;
const SPEED_CAP = 1.2;

class ElevenSession extends EventEmitter {
  constructor({ apiKey, voiceId, language = 'uk', voiceSpeed = 1.0 }) {
    super();
    if (!apiKey) throw new Error('ElevenSession: apiKey required');
    if (!voiceId) throw new Error('ElevenSession: voiceId required');
    this.apiKey = apiKey;
    this.voiceId = voiceId;
    this.language = language;
    this.voiceSpeed = clampSpeed(voiceSpeed);
    this.ws = null;
    this.ready = false;
    this.pending = [];           // chunks queued before upstream is ready
    this.chunkStartTs = 0;
    this.firstByteSent = false;
    this.closed = false;
  }

  open() {
    return new Promise((resolve, reject) => {
      const url = `wss://api.elevenlabs.io/v1/text-to-speech/${this.voiceId}/stream-input`
        + `?model_id=eleven_flash_v2_5`
        + `&output_format=pcm_24000`
        + `&language_code=${this.language}`
        + `&inactivity_timeout=180`;

      const ws = new WebSocket(url, { headers: { 'xi-api-key': this.apiKey } });
      this.ws = ws;

      ws.on('open', () => {
        if (this.closed) { try { ws.close(); } catch {} return; }
        try {
          ws.send(JSON.stringify({
            text: ' ',
            voice_settings: { stability: 0.5, similarity_boost: 0.8, speed: this.voiceSpeed },
          }));
        } catch (e) { reject(e); return; }
        this.ready = true;
        // Flush queued chunks
        for (const t of this.pending) this._sendChunkRaw(t);
        this.pending = [];
        resolve();
      });

      ws.on('message', (data) => {
        let payload;
        try { payload = JSON.parse(data.toString()); }
        catch (e) { this.emit('error', { message: 'parse: ' + e.message }); return; }
        if (payload.audio) {
          const buf = Buffer.from(payload.audio, 'base64');
          if (!this.firstByteSent && this.chunkStartTs) {
            const latencyMs = Date.now() - this.chunkStartTs;
            this.emit('first-byte', { latencyMs });
            this.firstByteSent = true;
          }
          this.emit('audio', buf);
        }
      });

      ws.on('error', (err) => this.emit('error', { message: err.message }));
      ws.on('close', () => {
        this.ready = false;
        this.emit('closed');
      });
    });
  }

  /**
   * Flush a translated text chunk. If the upstream isn't open yet, queue it.
   */
  chunk(text) {
    const trimmed = (text || '').trim();
    if (!trimmed) return;
    if (this.closed) return;
    if (!this.ready) { this.pending.push(trimmed); return; }
    this._sendChunkRaw(trimmed);
  }

  _sendChunkRaw(text) {
    this.chunkStartTs = Date.now();
    this.firstByteSent = false;
    try {
      this.ws.send(JSON.stringify({
        text: text + ' ',
        flush: true,
        voice_settings: { stability: 0.5, similarity_boost: 0.8, speed: this.voiceSpeed },
      }));
    } catch (e) {
      this.emit('error', { message: 'chunk send: ' + e.message });
    }
  }

  /** Update voice speed for subsequent chunks (clamped to ElevenLabs Flash range). */
  setSpeed(value) {
    this.voiceSpeed = clampSpeed(value);
  }

  /** Send EOS and close. Idempotent. */
  close() {
    if (this.closed) return;
    this.closed = true;
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      try { this.ws.send(JSON.stringify({ text: '' })); } catch {}
      try { this.ws.close(); } catch {}
    }
  }
}

function clampSpeed(v) {
  if (!Number.isFinite(v)) return 1.0;
  return Math.max(SPEED_MIN, Math.min(SPEED_CAP, v));
}

module.exports = { ElevenSession, SPEED_MIN, SPEED_CAP };
