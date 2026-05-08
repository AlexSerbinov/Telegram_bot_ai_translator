/**
 * Standalone test server for OpenAI Realtime *conversational* model
 * (regular `gpt-realtime`, NOT `gpt-realtime-translate`).
 *
 * Runs on its own port (default 3002) so it does not collide with the
 * main bot on 3001. Serves only:
 *   GET  /                       → /webapp/realtime-chat.html
 *   GET  /webapp/realtime-chat.html
 *   POST /session                → mint ephemeral client_secret
 *
 * Audio + events flow browser ↔ OpenAI directly via WebRTC. The server
 * only mints a short-lived token so OPENAI_API_KEY never reaches the
 * browser.
 *
 * Run:  npm run realtime:chat
 *       (or)  PORT=3002 node scripts/realtime-chat-server.js
 */
require('dotenv').config();

const express = require('express');
const path = require('path');

const PORT = Number(process.env.REALTIME_CHAT_PORT || process.env.PORT || 3002);
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const REALTIME_MODEL = process.env.OPENAI_REALTIME_CHAT_MODEL || 'gpt-realtime';
const CLIENT_SECRET_URL = 'https://api.openai.com/v1/realtime/client_secrets';

if (!OPENAI_API_KEY) {
  console.error('[realtime-chat] OPENAI_API_KEY is missing. Aborting.');
  process.exit(1);
}

const app = express();
app.use(express.json());

app.use('/webapp', express.static(path.join(__dirname, '..', 'src', 'webapp'), {
  setHeaders: (res) => {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');
  },
}));

app.get('/', (_req, res) => res.redirect('/webapp/realtime-chat.html'));

app.post('/session', async (req, res) => {
  try {
    const {
      voice = 'marin',
      instructions = '',
      inputLanguage = '',
      roomMode = false,            // multi-speaker / pickup background audio
      vadThreshold = 0.5,          // 0..1, lower = more sensitive (catches quieter speech)
      transcriptionModel = 'gpt-4o-transcribe',
    } = req.body || {};

    // In "room mode" we disable the noise reduction filter that prefers a single
    // close-talking voice, and lower the VAD threshold so quieter audio (e.g. a
    // YouTube video playing on speakers) still triggers a turn.
    const noiseReduction = roomMode ? null : { type: 'near_field' };
    const threshold = Math.max(0, Math.min(1, Number(vadThreshold) || 0.5));

    const sessionConfig = {
      session: {
        type: 'realtime',
        model: REALTIME_MODEL,
        audio: {
          input: {
            transcription: {
              model: transcriptionModel,
              ...(inputLanguage ? { language: inputLanguage } : {}),
            },
            noise_reduction: noiseReduction,
            turn_detection: {
              type: 'server_vad',
              threshold,
              prefix_padding_ms: 300,
              silence_duration_ms: 500,
            },
          },
          output: { voice },
        },
        ...(instructions ? { instructions } : {}),
      },
    };

    const r = await fetch(CLIENT_SECRET_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(sessionConfig),
    });

    if (!r.ok) {
      const err = await r.text();
      console.error(`[realtime-chat] client_secret API ${r.status}: ${err}`);
      return res.status(r.status).json({ error: err });
    }

    const data = await r.json();
    if (!data || typeof data.value !== 'string') {
      return res.status(502).json({ error: 'OpenAI did not return a client_secret value' });
    }

    console.log(`[realtime-chat] session created (model=${REALTIME_MODEL}, voice=${voice})`);
    res.json({
      client_secret: data.value,
      expires_at: data.expires_at ?? null,
      model: REALTIME_MODEL,
    });
  } catch (e) {
    console.error('[realtime-chat] session error:', e);
    res.status(500).json({ error: e.message });
  }
});

app.listen(PORT, () => {
  console.log(`🤖 OpenAI Realtime CHAT test server`);
  console.log(`   → http://localhost:${PORT}/webapp/realtime-chat.html`);
  console.log(`   model: ${REALTIME_MODEL}`);
});
