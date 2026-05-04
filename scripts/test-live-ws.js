/**
 * Smoke test for /ws/live — no microphone required.
 *
 * Validates the wire protocol:
 *   1. init (es→uk) → expect 'started'
 *   2. push silence PCM frames for ~3 s
 *   3. periodically push queue_state
 *   4. stop → expect 'done'
 *
 * Real-audio end-to-end testing happens in the browser with a live mic.
 */
const WebSocket = require('ws');

const URL = 'ws://localhost:3001/ws/live';
const SAMPLE_RATE = 16000;
const FRAME_MS = 100;
const FRAME_SAMPLES = (SAMPLE_RATE * FRAME_MS) / 1000; // 1600 samples = 3200 bytes

console.log(`[TEST] Connecting to ${URL}`);
const ws = new WebSocket(URL);
ws.binaryType = 'arraybuffer';

let started = false;
let metricsCount = 0;
let logsCount = 0;

ws.on('open', () => {
  console.log('[TEST] WS open, sending init…');
  ws.send(JSON.stringify({
    type: 'init', sourceLang: 'es', targetLang: 'uk', voiceSpeed: 1.0, autoSpeed: false,
  }));
});

ws.on('message', (data, isBinary) => {
  if (isBinary) {
    console.log(`[TEST] [BIN] ${data.byteLength} bytes (TTS audio)`);
    return;
  }
  let msg;
  try { msg = JSON.parse(data.toString()); } catch { return; }
  switch (msg.type) {
    case 'started':
      started = true;
      console.log('[TEST] received `started`');
      pushAudio();
      break;
    case 'src_partial':  /* spammy — ignore */ break;
    case 'src_final':    console.log(`[TEST] [src_final] "${msg.text.trim()}"`); break;
    case 'tgt_chunk':    console.log(`[TEST] [tgt_chunk] (${msg.mode}, ${msg.transMs}ms) "${msg.text}"`); break;
    case 'tts_first_byte': console.log(`[TEST] [tts_first_byte] ${msg.latencyMs}ms`); break;
    case 'metrics':      metricsCount++; if (metricsCount === 1) console.log(`[TEST] first [metrics] ${JSON.stringify(msg)}`); break;
    case 'log':          logsCount++; if (logsCount <= 5) console.log(`[TEST] [log] ${msg.level}: ${msg.msg}`); break;
    case 'error':        console.error(`[TEST] [error] ${msg.message}`); break;
    case 'done':         console.log('[TEST] [done]'); finish(0); break;
  }
});

ws.on('error', (e) => { console.error('[TEST] WS error', e.message); finish(1); });
ws.on('close', (code) => console.log(`[TEST] WS closed (code=${code})`));

let pushHandle = null;
function pushAudio() {
  // Push 30 silent frames (3 s) then ask to stop. Soniox won't return text on silence,
  // but we still validate that audio_b64 + queue_state + stop work without crashing.
  let i = 0;
  pushHandle = setInterval(() => {
    if (i >= 30) {
      clearInterval(pushHandle);
      console.log('[TEST] sending stop…');
      ws.send(JSON.stringify({ type: 'stop' }));
      return;
    }
    const silent = Buffer.alloc(FRAME_SAMPLES * 2); // s16le mono = 2 bytes/sample
    ws.send(JSON.stringify({ type: 'audio_b64', data: silent.toString('base64') }));
    ws.send(JSON.stringify({ type: 'queue_state', queueSec: 0.5 + Math.random() * 0.5 }));
    i++;
  }, FRAME_MS);
}

function finish(code) {
  if (pushHandle) clearInterval(pushHandle);
  console.log(`[TEST] ====================================`);
  console.log(`[TEST] started:    ${started}`);
  console.log(`[TEST] metrics:    ${metricsCount} ticks`);
  console.log(`[TEST] log lines:  ${logsCount}`);
  console.log(`[TEST] ====================================`);
  try { ws.close(); } catch {}
  setTimeout(() => process.exit(code), 200);
}

setTimeout(() => { console.error('[TEST] TIMEOUT after 12 s'); finish(1); }, 12000);
