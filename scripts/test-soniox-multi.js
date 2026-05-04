/**
 * Direct multi-chunk test for Soniox TTS — proves we can send N chunks back-to-back
 * over ONE WS connection (each as a fresh sub-stream) without "Stream not found" errors.
 */
require('dotenv').config();
const WebSocket = require('ws');
const crypto = require('crypto');

const API_KEY = process.env.SONIOX_TTS_API_KEY || process.env.SONIOX_API_KEY;
if (!API_KEY) { console.error('Missing SONIOX_TTS_API_KEY'); process.exit(1); }

const TEXTS = [
  'Привіт, друже.',
  'Як пройшов твій день?',
  'Сьогодні чудова погода.',
];

const ws = new WebSocket('wss://tts-rt.soniox.com/tts-websocket');
const t0 = Date.now();
const startTsByStream = {};
const audioBytesByStream = {};

ws.on('open', () => {
  console.log(`[TEST] Connected in ${Date.now() - t0}ms`);
  TEXTS.forEach((text, i) => {
    setTimeout(() => {
      const sid = 'multi-' + i + '-' + crypto.randomBytes(3).toString('hex');
      startTsByStream[sid] = Date.now();
      audioBytesByStream[sid] = 0;
      console.log(`[TEST] [chunk ${i+1}] open sub-stream ${sid}: "${text}"`);
      ws.send(JSON.stringify({
        api_key: API_KEY,
        stream_id: sid,
        model: 'tts-rt-v1',
        voice: 'Maya',
        language: 'uk',
        audio_format: 'pcm_s16le',
        sample_rate: 24000,
      }));
      ws.send(JSON.stringify({ text, text_end: true, stream_id: sid }));
    }, i * 800); // stagger by 800ms — simulates real chunk arrival
  });
  // Close 8s after the last chunk dispatch
  setTimeout(() => { ws.close(); }, TEXTS.length * 800 + 5000);
});

ws.on('message', (data) => {
  let msg; try { msg = JSON.parse(data.toString()); } catch { return; }
  if (msg.error_code || msg.error_message) {
    console.error(`[TEST] [ERROR ${msg.stream_id}] ${msg.error_code}: ${msg.error_message}`);
    return;
  }
  if (msg.audio && msg.stream_id) {
    if (audioBytesByStream[msg.stream_id] === 0) {
      const fb = Date.now() - startTsByStream[msg.stream_id];
      console.log(`[TEST] [first byte ${msg.stream_id}] ${fb}ms`);
    }
    audioBytesByStream[msg.stream_id] += Buffer.from(msg.audio, 'base64').length;
  }
  if (msg.terminated) {
    const bytes = audioBytesByStream[msg.stream_id] || 0;
    const sec = bytes / 2 / 24000;
    console.log(`[TEST] [done ${msg.stream_id}] ${bytes} bytes (${sec.toFixed(2)}s audio)`);
  }
});

ws.on('error', (e) => { console.error('[TEST] WS error', e.message); process.exit(1); });
ws.on('close', () => {
  console.log(`[TEST] WS closed. Total wallclock: ${Date.now() - t0}ms`);
  process.exit(0);
});
setTimeout(() => { console.error('[TEST] TIMEOUT'); process.exit(1); }, 15000);
