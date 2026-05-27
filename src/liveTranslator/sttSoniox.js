/**
 * Server-side Soniox real-time STT WebSocket client.
 *
 * Opens wss://stt-rt.soniox.com/transcribe-websocket, sends an initial JSON config
 * with API key + audio_format=s16le + language_hints, then forwards binary PCM
 * frames from the orchestrator. Emits 'partial'/'final' events with the merged
 * sliding-window text.
 *
 * Soniox returns each tick a `tokens` array where each token has `text` + `is_final`.
 * Final tokens are append-only; non-final tokens form the rolling interim window.
 *
 * Events:
 *   'partial'  (text)         — current interim text (replaces last)
 *   'final'    (text)         — newly finalized text segment (append to source)
 *   'endpoint' ()             — Soniox emitted `<end>` token (utterance boundary). Only fires
 *                               when SonioxSession is constructed with `endpointDetection:true`.
 *   'finished'                 — Soniox sent {finished:true}
 *   'error'    ({ message })  — transport / API error
 *   'closed'                   — upstream socket closed
 */
const EventEmitter = require('events');
const WebSocket = require('ws');

const URL_BASE = 'wss://stt-rt.soniox.com/transcribe-websocket';
const MODEL = 'stt-rt-v4';
const SAMPLE_RATE = 16000;

class SonioxSession extends EventEmitter {
  constructor({ apiKey, sourceLang = 'es', endpointDetection = false, endpointDelayMs = 700 }) {
    super();
    if (!apiKey) throw new Error('SonioxSession: apiKey required');
    this.apiKey = apiKey;
    this.sourceLang = sourceLang;
    this.endpointDetection = !!endpointDetection;
    this.endpointDelayMs = Number.isFinite(endpointDelayMs) ? endpointDelayMs : 700;
    this.ws = null;
    this.ready = false;
    this.audioBuffer = [];   // PCM frames received before upstream is open
    this.closed = false;
  }

  open() {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(URL_BASE);
      this.ws = ws;

      ws.on('open', () => {
        if (this.closed) { try { ws.close(); } catch {} return; }
        const config = {
          api_key: this.apiKey,
          model: MODEL,
          audio_format: 's16le',
          sample_rate: SAMPLE_RATE,
          num_channels: 1,
          language_hints: [this.sourceLang],
          enable_language_identification: false,
        };
        if (this.endpointDetection) {
          config.enable_endpoint_detection = true;
          config.max_endpoint_delay_ms = this.endpointDelayMs;
        }
        try { ws.send(JSON.stringify(config)); }
        catch (e) { reject(e); return; }
        this.ready = true;
        // Flush queued audio
        for (const buf of this.audioBuffer) { try { ws.send(buf); } catch {} }
        this.audioBuffer = [];
        resolve();
      });

      ws.on('message', (data) => {
        let msg;
        try { msg = JSON.parse(data.toString()); }
        catch (e) { this.emit('error', { message: 'parse: ' + e.message }); return; }

        if (msg.error_code || msg.error_message) {
          this.emit('error', { message: `${msg.error_code}: ${msg.error_message}` });
          return;
        }
        if (msg.finished) { this.emit('finished'); return; }

        if (Array.isArray(msg.tokens)) {
          let finalChunk = '', interimChunk = '', sawEnd = false;
          for (const t of msg.tokens) {
            if (t.text === '<end>') { sawEnd = true; continue; }
            if (t.is_final) finalChunk += t.text;
            else interimChunk += t.text;
          }
          if (finalChunk) this.emit('final', finalChunk);
          // Emit interim every tick (even if empty, to clear stale)
          this.emit('partial', interimChunk);
          // Endpoint must follow the final it caps, so listeners can flush in order.
          if (sawEnd) this.emit('endpoint');
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
   * Forward one PCM frame (raw s16le 16 kHz mono) to Soniox.
   * Buffers until the WS handshake is done.
   * @param {Buffer} pcm
   */
  feed(pcm) {
    if (this.closed) return;
    if (!Buffer.isBuffer(pcm)) pcm = Buffer.from(pcm);
    if (!this.ready) { this.audioBuffer.push(pcm); return; }
    try { this.ws.send(pcm); }
    catch (e) { this.emit('error', { message: 'feed: ' + e.message }); }
  }

  /** Send empty frame (Soniox EOS) and close. Idempotent. */
  close() {
    if (this.closed) return;
    this.closed = true;
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      try { this.ws.send(Buffer.alloc(0)); } catch {}
      try { this.ws.close(); } catch {}
    }
  }
}

module.exports = { SonioxSession, SAMPLE_RATE };
