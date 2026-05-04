/**
 * Smoke-test the Palabra WebSocket protocol:
 *   1. Get session via our backend relay
 *   2. Open WS to Palabra with publisher token
 *   3. Send set_task (es → uk)
 *   4. Log all messages for ~6s and exit
 *
 * No microphone — just confirms task is accepted and pipeline starts.
 */
const WebSocket = require('ws');

const SAMPLE_RATE = 16000;
const SOURCE_LANG = process.argv[2] || 'es';
const TARGET_LANG = process.argv[3] || 'uk';

(async () => {
  const r = await fetch('http://localhost:3001/api/palabra/session', { method: 'POST' });
  if (!r.ok) {
    console.error('[FAIL] /api/palabra/session', r.status, await r.text());
    process.exit(1);
  }
  const session = await r.json();
  console.log('[OK] session id:', session.id?.slice(0, 40), '...');
  console.log('[OK] ws_url:', session.ws_url);

  const url = `${session.ws_url}?token=${session.publisher}`;
  const ws = new WebSocket(url);
  ws.binaryType = 'arraybuffer';

  ws.on('open', () => {
    console.log('[OK] connected to Palabra WS');
    const setTask = {
      message_type: 'set_task',
      data: {
        input_stream: {
          content_type: 'audio',
          source: { type: 'ws', format: 'pcm_s16le', sample_rate: SAMPLE_RATE, channels: 1 },
        },
        output_stream: {
          content_type: 'audio',
          target: { type: 'ws', format: 'pcm_s16le', sample_rate: 24000, channels: 1 },
        },
        pipeline: {
          transcription: { source_language: SOURCE_LANG },
          translations: [{ target_language: TARGET_LANG, speech_generation: {} }],
        },
      },
    };
    ws.send(JSON.stringify(setTask));
    console.log(`[SENT] set_task (${SOURCE_LANG}→${TARGET_LANG})`);
  });

  ws.on('message', (data, isBinary) => {
    if (isBinary) {
      console.log(`[BIN ] ${data.length} bytes`);
    } else {
      try {
        const msg = JSON.parse(data.toString());
        const preview = JSON.stringify(msg).slice(0, 220);
        console.log(`[RECV] ${msg.message_type || 'no-type'}: ${preview}`);
      } catch {
        console.log('[RECV] raw:', data.toString().slice(0, 200));
      }
    }
  });

  ws.on('error', (e) => console.error('[WS ERR]', e.message));
  ws.on('close', (code, reason) => {
    console.log(`[CLOSE] code=${code} reason="${reason}"`);
    process.exit(0);
  });

  setTimeout(() => {
    console.log('[TIMEOUT] 6s elapsed, closing');
    ws.close(1000);
  }, 6000);
})();
