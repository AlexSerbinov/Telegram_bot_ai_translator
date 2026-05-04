/**
 * Persistent Soniox TTS WebSocket session — alternative provider to ttsEleven.js.
 *
 * Soniox TTS is a *multi-stream* protocol: one WS connection can host many
 * sub-streams keyed by stream_id. Each chunk() opens a fresh sub-stream
 * (config + text + text_end:true), the server returns audio frames tagged
 * with that stream_id, and a final { terminated:true } closes it.
 *
 * IMPORTANT — sub-streams are SERIALIZED in this implementation. We open the
 * next sub-stream only after the previous one's `terminated:true` arrives.
 * Without serialization, audio frames from concurrent sub-streams interleave
 * on the WS and the listener hears voices cutting each other off mid-word.
 *
 * Endpoint: wss://tts-rt.soniox.com/tts-websocket
 * Voice "Maya" (or any of the 12 Soniox voices) is inherently multilingual; we
 * pass `language` per sub-stream just for pronunciation hint.
 *
 * No server-side speed control — `setSpeed()` is a no-op for interface parity.
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
    this.ws = null;
    this.ready = false;
    this.queue = [];                          // pending text chunks awaiting synthesis
    this.activeStreamId = null;               // currently-streaming sub-stream's id
    this.activeStreamStartTs = 0;
    this.firstByteSent = false;
    this.closed = false;
  }

  open() {
    return new Promise((resolve) => {
      const ws = new WebSocket(URL);
      this.ws = ws;

      ws.on('open', () => {
        if (this.closed) { try { ws.close(); } catch {} return; }
        this.ready = true;
        this._drain();
        resolve();
      });

      ws.on('message', (data) => {
        let payload;
        try { payload = JSON.parse(data.toString()); }
        catch (e) { this.emit('error', { message: 'parse: ' + e.message }); return; }

        if (payload.error_code || payload.error_message) {
          this.emit('error', { message: `${payload.error_code || ''}: ${payload.error_message || JSON.stringify(payload)}` });
          // Advance — don't deadlock the queue on a single failure.
          if (payload.stream_id && payload.stream_id === this.activeStreamId) {
            this.activeStreamId = null;
            this._drain();
          }
          return;
        }

        // Drop frames from any stream that isn't the currently-active one. In practice this
        // shouldn't happen because we serialize, but guard against late frames after errors.
        if (payload.stream_id && payload.stream_id !== this.activeStreamId) return;

        if (payload.audio) {
          if (!this.firstByteSent && this.activeStreamStartTs) {
            this.emit('first-byte', { latencyMs: Date.now() - this.activeStreamStartTs });
            this.firstByteSent = true;
          }
          this.emit('audio', Buffer.from(payload.audio, 'base64'));
        }

        if (payload.terminated) {
          this.activeStreamId = null;
          this._drain();
        }
      });

      ws.on('error', (err) => this.emit('error', { message: err.message }));
      ws.on('close', () => {
        this.ready = false;
        this.activeStreamId = null;
        this.queue = [];
        this.emit('closed');
      });
    });
  }

  /** Queue a text chunk. Synthesis is serialized — frames stay in order. */
  chunk(text) {
    const trimmed = (text || '').trim();
    if (!trimmed || this.closed) return;
    this.queue.push(trimmed);
    this._drain();
  }

  /** Pull next chunk off the queue and open a sub-stream for it. No-op while one is active. */
  _drain() {
    if (!this.ready || this.activeStreamId || this.closed) return;
    const text = this.queue.shift();
    if (!text) return;

    const streamId = 'live-' + Date.now().toString(36) + '-' + crypto.randomBytes(3).toString('hex');
    this.activeStreamId = streamId;
    this.activeStreamStartTs = Date.now();
    this.firstByteSent = false;

    try {
      // 1) config (= "start") for this sub-stream
      this.ws.send(JSON.stringify({
        api_key: this.apiKey,
        stream_id: streamId,
        model: this.model,
        voice: this.voice,
        language: this.language,
        audio_format: 'pcm_s16le',
        sample_rate: SAMPLE_RATE,
      }));
      // 2) text + text_end on the same stream_id (one-shot per chunk)
      this.ws.send(JSON.stringify({
        text: text + ' ',
        text_end: true,
        stream_id: streamId,
      }));
    } catch (e) {
      this.emit('error', { message: 'sub-stream send: ' + e.message });
      this.activeStreamId = null;
      // Try to keep the queue moving despite this failure.
      this._drain();
    }
  }

  /** No server-side speed; kept for interface parity with ElevenSession. */
  setSpeed(_value) { /* no-op */ }

  close() {
    if (this.closed) return;
    this.closed = true;
    this.queue = [];
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      try { this.ws.close(); } catch {}
    }
  }
}

module.exports = { SonioxTtsSession, SAMPLE_RATE };
