/**
 * End-to-end test for the persistent /ws/tts proxy.
 * Protocol: init → chunk → chunk → … → end.
 * Verifies first-byte latency, PCM bytes streaming, and clean shutdown.
 */
const WebSocket = require('ws');

const chunks = [
  process.argv[2] || 'Привіт, друже,',
  process.argv[3] || 'як пройшов твій день?',
];
const language = process.argv[4] || 'uk';
const url = 'ws://localhost:3001/ws/tts';

console.log(`[TEST] Connecting to ${url}`);
const ws = new WebSocket(url);

let totalBytes = 0;
let chunkCount = 0;
let firstByteAt = null;
const tStart = Date.now();

ws.on('open', () => {
  console.log(`[TEST] Connected in ${Date.now() - tStart}ms`);
  console.log(`[TEST] Sending init (lang=${language})`);
  ws.send(JSON.stringify({ type: 'init', language }));

  // fire chunks with a small delay so it mimics a streaming session
  setTimeout(() => {
    console.log(`[TEST] Sending chunk 1: "${chunks[0]}"`);
    ws.send(JSON.stringify({ type: 'chunk', text: chunks[0] }));
  }, 100);
  setTimeout(() => {
    console.log(`[TEST] Sending chunk 2: "${chunks[1]}"`);
    ws.send(JSON.stringify({ type: 'chunk', text: chunks[1] }));
  }, 1500);
  setTimeout(() => {
    console.log(`[TEST] Sending end`);
    ws.send(JSON.stringify({ type: 'end' }));
  }, 4000);
});

ws.on('message', (data, isBinary) => {
  if (isBinary) {
    if (firstByteAt === null) firstByteAt = Date.now() - tStart;
    totalBytes += data.length;
    chunkCount++;
  } else {
    try {
      const msg = JSON.parse(data.toString());
      console.log(`[TEST] CTRL:`, msg);
      if (msg.type === 'done') {
        const seconds = totalBytes / 2 / 24000;
        console.log(`[TEST] ====================================`);
        console.log(`[TEST] First binary byte:  ${firstByteAt}ms wall`);
        console.log(`[TEST] Total chunks:       ${chunkCount}`);
        console.log(`[TEST] Total PCM bytes:    ${totalBytes}`);
        console.log(`[TEST] Audio duration:     ${seconds.toFixed(2)}s @ 24kHz mono 16-bit`);
        console.log(`[TEST] Wallclock total:    ${Date.now() - tStart}ms`);
        console.log(`[TEST] ====================================`);
        ws.close();
        setTimeout(() => process.exit(0), 200);
      }
    } catch (e) {
      console.error('[TEST] Parse error', e);
    }
  }
});

ws.on('error', (e) => { console.error('[TEST] WS error', e.message); process.exit(1); });
ws.on('close', (code) => console.log(`[TEST] WS closed (code=${code})`));

setTimeout(() => { console.error('[TEST] TIMEOUT after 12s'); process.exit(1); }, 12000);
