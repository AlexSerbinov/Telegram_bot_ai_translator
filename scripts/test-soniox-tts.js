/**
 * Direct smoke test for Soniox TTS — bypasses our /ws/live, talks straight to Soniox.
 * Uses SONIOX_TTS_API_KEY from .env. Synthesizes a Ukrainian sentence and reports
 * first-byte latency + total PCM bytes received.
 */
require('dotenv').config();
const WebSocket = require('ws');

const API_KEY = process.env.SONIOX_TTS_API_KEY || process.env.SONIOX_API_KEY;
if (!API_KEY) { console.error('Missing SONIOX_TTS_API_KEY / SONIOX_API_KEY'); process.exit(1); }

const TEXT = process.argv[2] || 'Привіт, друже, як пройшов твій день?';
const LANG = process.argv[3] || 'uk';
const VOICE = process.argv[4] || 'Maya';
const STREAM_ID = 'test-' + Date.now();

const ws = new WebSocket('wss://tts-rt.soniox.com/tts-websocket');
let firstByteAt = null;
let totalBytes = 0;
let chunks = 0;
const t0 = Date.now();

ws.on('open', () => {
  console.log(`[TEST] Connected in ${Date.now() - t0}ms`);
  ws.send(JSON.stringify({
    api_key: API_KEY,
    stream_id: STREAM_ID,
    model: 'tts-rt-v1',
    voice: VOICE,
    language: LANG,
    audio_format: 'pcm_s16le',
    sample_rate: 24000,
  }));
  console.log(`[TEST] Sent config (lang=${LANG}, voice=${VOICE})`);
  // Send text
  setTimeout(() => {
    ws.send(JSON.stringify({ text: TEXT, text_end: false, stream_id: STREAM_ID }));
    console.log(`[TEST] Sent text: "${TEXT}"`);
    setTimeout(() => {
      ws.send(JSON.stringify({ text: '', text_end: true, stream_id: STREAM_ID }));
      console.log('[TEST] Sent text_end');
    }, 100);
  }, 50);
});

ws.on('message', (data) => {
  let msg;
  try { msg = JSON.parse(data.toString()); } catch { return; }
  if (msg.error_code || msg.error_message) {
    console.error(`[TEST] [ERROR] ${msg.error_code}: ${msg.error_message}`);
    process.exit(1);
  }
  if (msg.audio) {
    if (firstByteAt === null) {
      firstByteAt = Date.now() - t0;
      console.log(`[TEST] First audio byte in ${firstByteAt}ms`);
    }
    chunks++;
    totalBytes += Buffer.from(msg.audio, 'base64').length;
  }
  if (msg.terminated) {
    const sec = totalBytes / 2 / 24000;
    console.log(`[TEST] ====================================`);
    console.log(`[TEST] First byte:    ${firstByteAt}ms`);
    console.log(`[TEST] Total chunks:  ${chunks}`);
    console.log(`[TEST] Total PCM:     ${totalBytes} bytes`);
    console.log(`[TEST] Duration:      ${sec.toFixed(2)}s @ 24kHz mono 16-bit`);
    console.log(`[TEST] Wallclock:     ${Date.now() - t0}ms`);
    console.log(`[TEST] ====================================`);
    ws.close();
    setTimeout(() => process.exit(0), 200);
  }
});

ws.on('error', (e) => { console.error('[TEST] WS error', e.message); process.exit(1); });
ws.on('close', (code) => console.log(`[TEST] WS closed (code=${code})`));
setTimeout(() => { console.error('[TEST] TIMEOUT'); process.exit(1); }, 15000);
