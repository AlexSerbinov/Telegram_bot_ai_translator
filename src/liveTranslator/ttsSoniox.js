/**
 * Persistent Soniox TTS WebSocket session — drop-in alternative to ttsEleven.js.
 *
 * Same EventEmitter shape as ElevenSession so LiveTranslatorSession can swap providers.
 * Endpoint: wss://tts-rt.soniox.com/tts-websocket
 *
 * Wire protocol:
 *   1. Send initial JSON config (api_key + model + voice + language + audio_format)
 *   2. For each new translation chunk → { text, text_end:false, stream_id }
 *   3. To close → { text:'', text_end:true, stream_id }
 *   4. Server returns { audio:<base64 PCM s16le>, audio_end, stream_id } repeatedly,
 *      then a terminal { terminated:true, stream_id } before closing.
 *
 * Voice selection: every Soniox voice handles all 60+ languages with consistent timbre,
 * so we don't need a per-language voice table. We pass `language` per session for
 * pronunciation hint; voice stays the same.
 *
 * Note: Soniox TTS API does NOT expose a server-side speed parameter. Speed is
 * applied client-side via playbackRate (already done in the Mini App). setSpeed() is a
 * no-op here — kept for interface parity with ElevenSession.
 */
const EventEmitter = require('events');
const WebSocket = require('ws');
const crypto = require('crypto');

const URL = 'wss://tts-rt.soniox.com/tts-websocket';
const SAMPLE_RATE = 24000;

class SonioxTtsSession extends EventEmitter {
  constructor({ apiKey, model = 'tts-rt-v1', voice = 'Maya', language = 'uk' }) {
    super();
    if (!apiKey) throw new Error('SonioxTtsSession: apiKey required');
    this.apiKey = apiKey;
    this.model = model;
    this.voice = voice;
    this.language = language;
    this.streamId = 'live-' + crypto.randomBytes(6).toString('hex');
    this.ws = null;
    this.ready = false;
    this.pending = [];
    this.chunkStartTs = 0;
    this.firstByteSent = false;
    this.closed = false;
  }

  open() {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(URL);
      this.ws = ws;

      ws.on('open', () => {
        if (this.closed) { try { ws.close(); } catch {} return; }
        const config = {
          api_key: this.apiKey,
          stream_id: this.streamId,
          model: this.model,
          voice: this.voice,
          language: this.language,
          audio_format: 'pcm_s16le',
          sample_rate: SAMPLE_RATE,
        };
        try { ws.send(JSON.stringify(config)); }
        catch (e) { reject(e); return; }
        this.ready = true;
        for (const t of this.pending) this._sendChunkRaw(t);
        this.pending = [];
        resolve();
      });

      ws.on('message', (data) => {
        let payload;
        try { payload = JSON.parse(data.toString()); }
        catch (e) { this.emit('error', { message: 'parse: ' + e.message }); return; }

        if (payload.error_code || payload.error_message) {
          this.emit('error', { message: `${payload.error_code || ''}: ${payload.error_message || JSON.stringify(payload)}` });
          return;
        }
        if (payload.audio) {
          const buf = Buffer.from(payload.audio, 'base64');
          if (!this.firstByteSent && this.chunkStartTs) {
            const latencyMs = Date.now() - this.chunkStartTs;
            this.emit('first-byte', { latencyMs });
            this.firstByteSent = true;
          }
          this.emit('audio', buf);
        }
        if (payload.terminated) {
          // Soniox confirms end-of-stream
        }
      });

      ws.on('error', (err) => this.emit('error', { message: err.message }));
      ws.on('close', () => { this.ready = false; this.emit('closed'); });
    });
  }

  /** Flush a translated text chunk; queue if upstream not ready. */
  chunk(text) {
    const trimmed = (text || '').trim();
    if (!trimmed || this.closed) return;
    if (!this.ready) { this.pending.push(trimmed); return; }
    this._sendChunkRaw(trimmed);
  }

  _sendChunkRaw(text) {
    this.chunkStartTs = Date.now();
    this.firstByteSent = false;
    try {
      this.ws.send(JSON.stringify({
        text: text + ' ',
        text_end: false,
        stream_id: this.streamId,
      }));
    } catch (e) {
      this.emit('error', { message: 'chunk send: ' + e.message });
    }
  }

  /** No server-side speed control; kept for interface parity. */
  setSpeed(_value) { /* no-op */ }

  close() {
    if (this.closed) return;
    this.closed = true;
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      try { this.ws.send(JSON.stringify({ text: '', text_end: true, stream_id: this.streamId })); } catch {}
      try { this.ws.close(); } catch {}
    }
  }
}

module.exports = { SonioxTtsSession, SAMPLE_RATE };
