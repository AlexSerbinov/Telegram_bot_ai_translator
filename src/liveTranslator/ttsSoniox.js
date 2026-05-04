/**
 * Persistent Soniox TTS WebSocket session — alternative provider to ttsEleven.js.
 *
 * Soniox TTS is a *multi-stream* protocol: one WS connection can host many
 * concurrent or sequential streams, each with its own stream_id. There is NO
 * persistent "input stream" the way ElevenLabs streaming-input has. Each
 * synthesis request must:
 *   1. Send a config (api_key + stream_id + model + voice + ...) to open a sub-stream
 *   2. Send text + text_end:true on that same stream_id
 *   3. Server returns audio frames + a final { terminated:true } for that stream_id
 * The connection stays open and we open a fresh sub-stream per chunk().
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
    this.pending = [];                        // chunks queued before WS handshake done
    this.startTsByStream = new Map();         // stream_id → ts of opening (for first-byte)
    this.firstByteSentByStream = new Set();   // streams whose first-byte has been emitted
    this.closed = false;
  }

  open() {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(URL);
      this.ws = ws;

      ws.on('open', () => {
        if (this.closed) { try { ws.close(); } catch {} return; }
        this.ready = true;
        // Flush any chunks that arrived during handshake
        for (const t of this.pending) this._openSubStream(t);
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
          const sid = payload.stream_id;
          const startTs = sid ? this.startTsByStream.get(sid) : null;
          if (startTs && sid && !this.firstByteSentByStream.has(sid)) {
            const latencyMs = Date.now() - startTs;
            this.emit('first-byte', { latencyMs });
            this.firstByteSentByStream.add(sid);
          }
          this.emit('audio', buf);
        }

        if (payload.terminated && payload.stream_id) {
          this.startTsByStream.delete(payload.stream_id);
          this.firstByteSentByStream.delete(payload.stream_id);
        }
      });

      ws.on('error', (err) => this.emit('error', { message: err.message }));
      ws.on('close', () => { this.ready = false; this.emit('closed'); });
    });
  }

  /**
   * Synthesize one text chunk as a fresh Soniox sub-stream.
   * Stream_id is unique per chunk; many can be in flight concurrently.
   */
  chunk(text) {
    const trimmed = (text || '').trim();
    if (!trimmed || this.closed) return;
    if (!this.ready) { this.pending.push(trimmed); return; }
    this._openSubStream(trimmed);
  }

  _openSubStream(text) {
    const streamId = 'live-' + Date.now().toString(36) + '-' + crypto.randomBytes(3).toString('hex');
    this.startTsByStream.set(streamId, Date.now());

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
    }
  }

  /** No server-side speed; kept for interface parity with ElevenSession. */
  setSpeed(_value) { /* no-op */ }

  close() {
    if (this.closed) return;
    this.closed = true;
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      try { this.ws.close(); } catch {}
    }
  }
}

module.exports = { SonioxTtsSession, SAMPLE_RATE };
