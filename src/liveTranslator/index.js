/**
 * Live translator engine — public surface.
 *
 *   const { attachLiveWs } = require('./liveTranslator');
 *   attachLiveWs(httpServer, { groqApiKey, sonioxApiKey, elevenApiKey, elevenVoiceId });
 *
 * Registers a WebSocket route at `/ws/live` that orchestrates a full
 * speech-to-speech translation per connection. See plan/inherited-hopping-conway.md
 * for the wire protocol.
 */
const WebSocket = require('ws');
const { LiveTranslatorSession } = require('./session');

function attachLiveWs({ groqApiKey, sonioxApiKey, elevenApiKey, elevenVoiceId, logger = console }) {
  if (!groqApiKey || !sonioxApiKey || !elevenApiKey || !elevenVoiceId) {
    throw new Error('attachLiveWs: missing required API keys (groq/soniox/eleven/voiceId)');
  }
  // Caller is responsible for routing /ws/live upgrades into this WSS via handleUpgrade().
  const wss = new WebSocket.Server({ noServer: true });

  wss.on('connection', (clientWs) => {
    logger.info('[Live] client connected');
    const session = new LiveTranslatorSession({ groqApiKey, sonioxApiKey, elevenApiKey, elevenVoiceId });

    // Wire session events → client frames
    const safeSend = (obj) => { try { clientWs.send(JSON.stringify(obj)); } catch {} };
    const safeSendBinary = (buf) => { try { clientWs.send(buf, { binary: true }); } catch {} };

    session.on('src_partial', (m) => safeSend({ type: 'src_partial', text: m.text }));
    session.on('src_final',   (m) => safeSend({ type: 'src_final',   text: m.text }));
    session.on('tgt_chunk',   (m) => safeSend({ type: 'tgt_chunk',   ...m }));
    session.on('tts_audio',   (buf) => safeSendBinary(buf));
    session.on('tts_first_byte', (m) => safeSend({ type: 'tts_first_byte', latencyMs: m.latencyMs }));
    session.on('metrics',     (m) => safeSend({ type: 'metrics', ...m }));
    session.on('log',         (m) => safeSend({ type: 'log', level: m.level, msg: m.msg }));
    session.on('error',       (m) => safeSend({ type: 'error', message: m.message }));
    session.on('finished',    () => safeSend({ type: 'done' }));

    clientWs.on('message', async (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); } catch { return; }
      try {
        switch (msg.type) {
          case 'init':
            await session.start({
              sourceLang:  msg.sourceLang,
              targetLang:  msg.targetLang,
              voiceSpeed:  msg.voiceSpeed,
              autoSpeedOn: msg.autoSpeed,
            });
            safeSend({ type: 'started' });
            break;
          case 'audio_b64':
            if (msg.data) session.feedAudio(Buffer.from(msg.data, 'base64'));
            break;
          case 'queue_state':
            session.reportClientQueue(msg.queueSec);
            break;
          case 'set_speed':
            session.setSpeed(msg.value);
            break;
          case 'set_auto':
            session.setAuto(msg.enabled);
            break;
          case 'stop':
            await session.stop();
            break;
        }
      } catch (e) {
        logger.error('[Live] message handling error:', e);
        safeSend({ type: 'error', message: e.message });
      }
    });

    clientWs.on('close', async () => {
      logger.info('[Live] client disconnected');
      try { await session.stop(); } catch {}
    });
  });

  return wss;
}

module.exports = { attachLiveWs, LiveTranslatorSession };
