const express = require('express');
const path = require('path');
const http = require('http');
const WebSocket = require('ws');
const { config } = require('./config/config');
const logger = require('./utils/logger');
const elevenLabsService = require('./services/elevenLabsService');
const geminiService = require('./services/geminiService');
const groqService = require('./services/groqService');
const databaseService = require('./services/databaseService');
const { attachLiveWs } = require('./liveTranslator');

// Extended language map for the live translator demo — broader than config.languages
// (which is only the 6 languages exposed in the Telegram bot UI).
const LANG_NAMES = {
  es: 'Spanish', en: 'English', ru: 'Russian', uk: 'Ukrainian',
  de: 'German', fr: 'French', it: 'Italian', pt: 'Portuguese',
  pl: 'Polish', tr: 'Turkish', nl: 'Dutch', cs: 'Czech',
  ja: 'Japanese', zh: 'Chinese', ar: 'Arabic',
};

function createServer() {
  const app = express();
  app.use(express.json());

  // Serve Mini App static files. Disable caching so fresh HTML/JS is fetched
  // every time — iOS Telegram WebView holds onto old versions otherwise.
  app.use('/webapp', express.static(path.join(__dirname, 'webapp'), {
    setHeaders: (res) => {
      res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0');
      res.setHeader('Pragma', 'no-cache');
      res.setHeader('Expires', '0');
    },
  }));

  // Generate single-use STT token (provider-dependent)
  app.get('/api/token', async (req, res) => {
    try {
      if (config.stt.provider === 'elevenlabs') {
        const token = await elevenLabsService.generateRealtimeToken();
        res.json({ token });
      } else {
        const response = await fetch('https://api.soniox.com/v1/auth/temporary-api-key', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${config.soniox.apiKey}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            usage_type: 'transcribe_websocket',
            expires_in_seconds: 300
          })
        });
        if (!response.ok) throw new Error(`Soniox API error: ${response.status}`);
        const data = await response.json();
        res.json({ token: data.api_key });
      }
    } catch (error) {
      logger.error('Error generating STT token:', error);
      res.status(500).json({ error: 'Failed to generate token' });
    }
  });

  // Translate text via Gemini
  app.post('/api/translate', async (req, res) => {
    try {
      const { text, fromLanguage, toLanguage } = req.body;
      if (!text || !fromLanguage || !toLanguage) {
        return res.status(400).json({ error: 'Missing required fields: text, fromLanguage, toLanguage' });
      }

      const fromLang = config.languages[fromLanguage];
      const toLang = config.languages[toLanguage];
      if (!fromLang || !toLang) {
        return res.status(400).json({ error: 'Unsupported language code' });
      }

      const translationService = config.translation.provider === 'groq' ? groqService : geminiService;
      const translation = await translationService.translateText(text, fromLang.name, toLang.name);
      res.json({ translation, fromLanguage, toLanguage });
    } catch (error) {
      logger.error('Error translating text:', error);
      res.status(500).json({ error: 'Translation failed' });
    }
  });

  // Auto-detect source language from pair and translate to opposite language
  app.post('/api/translate-auto', async (req, res) => {
    try {
      const { text, primaryLanguage, secondaryLanguage } = req.body;
      if (!text || !primaryLanguage || !secondaryLanguage) {
        return res.status(400).json({ error: 'Missing required fields: text, primaryLanguage, secondaryLanguage' });
      }

      const primary = config.languages[primaryLanguage];
      const secondary = config.languages[secondaryLanguage];
      if (!primary || !secondary) {
        return res.status(400).json({ error: 'Unsupported language code' });
      }
      if (primaryLanguage === secondaryLanguage) {
        return res.status(400).json({ error: 'Languages must be different' });
      }

      const translationService = config.translation.provider === 'groq' ? groqService : geminiService;
      const detectedLanguage = await translationService.detectTextLanguage(text, [primaryLanguage, secondaryLanguage]);
      const targetLanguage = detectedLanguage === primaryLanguage ? secondaryLanguage : primaryLanguage;
      const fromLang = config.languages[detectedLanguage];
      const toLang = config.languages[targetLanguage];
      const translation = await translationService.translateText(text, fromLang.name, toLang.name);

      res.json({
        translation,
        detectedLanguage,
        targetLanguage
      });
    } catch (error) {
      logger.error('Error in auto translation:', error);
      res.status(500).json({ error: 'Auto translation failed' });
    }
  });

  // Palabra.ai session — relay to keep client_secret server-side only
  app.post('/api/palabra/session', async (req, res) => {
    try {
      if (!config.palabra.clientId || !config.palabra.clientSecret) {
        return res.status(500).json({ error: 'Palabra credentials not configured' });
      }
      const r = await fetch(config.palabra.sessionUrl, {
        method: 'POST',
        headers: {
          'ClientId': config.palabra.clientId,
          'ClientSecret': config.palabra.clientSecret,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ data: { subscriber_count: 0, publisher_can_subscribe: true } }),
      });
      if (!r.ok) {
        const err = await r.text();
        logger.error(`[Palabra] session API ${r.status}: ${err}`);
        return res.status(r.status).json({ error: err });
      }
      const raw = await r.json();
      const session = raw?.data || raw;
      logger.info(`[Palabra] session created: id=${session.id}, ws=${session.ws_url}`);
      res.json(session);
    } catch (e) {
      logger.error('[Palabra] session error:', e);
      res.status(500).json({ error: e.message });
    }
  });

  // Fast streaming translator via Groq gpt-oss-20b.
  // INCREMENTAL mode: when contextSrc/contextTrans are provided, the body `text`
  // is treated as the NEW segment only, and the prior context is shown to the
  // model as previously-spoken context. The model returns ONLY the new chunk
  // — never repeats the prior translation. This avoids the looping/hallucination
  // that happens when a growing source is re-translated from scratch each time.
  app.post('/api/translate-fast', async (req, res) => {
    try {
      const {
        text,
        fromLanguage = 'es',
        toLanguage = 'uk',
        contextSrc = '',
        contextTrans = '',
      } = req.body;
      if (!text) return res.status(400).json({ error: 'Missing text' });

      const fromLang = LANG_NAMES[fromLanguage];
      const toLang = LANG_NAMES[toLanguage];
      if (!fromLang || !toLang) return res.status(400).json({ error: `Unsupported language pair: ${fromLanguage}→${toLanguage}` });

      const hasContext = contextSrc && contextTrans;
      const systemPrompt = hasContext
        ? `You are a real-time streaming translator from ${fromLang} into ${toLang}.
Previously spoken context (already delivered to the listener — DO NOT re-translate or repeat any of it):
  Source:      "${contextSrc}"
  Translation: "${contextTrans}"

Translate ONLY the NEW source segment provided by the user, as a natural continuation that flows from the previous context. Match the previous translation's tense, gender and tone. Output ONLY the translation of the new segment — no echoes of prior context, no labels, no quotes, no explanations.`
        : `You are a translation engine from ${fromLang} into ${toLang}. Translate the user text. Output only the translation, no quotes, no explanations.`;

      const t0 = Date.now();
      const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${config.groq.apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'openai/gpt-oss-120b',
          messages: [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: text },
          ],
          temperature: 0.2,
        }),
      });

      if (!response.ok) {
        const err = await response.text();
        throw new Error(`Groq ${response.status}: ${err}`);
      }
      const data = await response.json();
      const translation = data.choices[0].message.content.trim();
      const elapsedMs = Date.now() - t0;

      res.json({ translation, elapsedMs });
    } catch (error) {
      logger.error('Error in translate-fast:', error);
      res.status(500).json({ error: error.message || 'Translation failed' });
    }
  });

  // OpenAI Realtime Translation — issue ephemeral client_secret for browser WebRTC.
  // Real audio flows directly browser ↔ OpenAI; this server only mints the secret
  // so OPENAI_API_KEY never reaches the browser. Mirrors openai-cookbook
  // /examples/voice_solutions/realtime_translation_guide/browser-translation-demo.
  app.post('/api/realtime/session', async (req, res) => {
    try {
      const { targetLanguage } = req.body || {};
      if (!targetLanguage || typeof targetLanguage !== 'string') {
        return res.status(400).json({ error: 'Missing targetLanguage' });
      }
      if (!config.openaiRealtime.apiKey) {
        return res.status(500).json({ error: 'OPENAI_API_KEY is not configured' });
      }

      const r = await fetch(config.openaiRealtime.clientSecretUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${config.openaiRealtime.apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          session: {
            model: config.openaiRealtime.model,
            audio: {
              input: {
                transcription: { model: config.openaiRealtime.transcriptionModel },
                // near_field cleans up mobile mic noise; null left the API to
                // do whatever default it uses, which seemed to underperform.
                noise_reduction: { type: 'near_field' },
                // Explicit VAD config — Mini App users were reporting sessions
                // dropping mid-flow after the first turn. Default VAD seems
                // to commit a turn then not re-arm reliably; this matches the
                // config that keeps Chat tab stable.
                turn_detection: {
                  type: 'server_vad',
                  threshold: 0.5,
                  prefix_padding_ms: 300,
                  silence_duration_ms: 800,
                },
              },
              output: { language: targetLanguage },
            },
          },
        }),
      });

      if (!r.ok) {
        const errText = await r.text();
        logger.error(`[Realtime] client_secret API ${r.status}: ${errText}`);
        return res.status(r.status).json({ error: errText });
      }
      const data = await r.json();
      if (!data || typeof data.value !== 'string') {
        return res.status(502).json({ error: 'OpenAI did not return a client_secret value' });
      }
      logger.info(`[Realtime] session created (lang=${targetLanguage}, model=${config.openaiRealtime.model})`);
      res.json({
        client_secret: data.value,
        expires_at: data.expires_at ?? null,
        model: config.openaiRealtime.model,
        targetLanguage,
      });
    } catch (e) {
      logger.error('[Realtime] session error:', e);
      res.status(500).json({ error: e.message });
    }
  });

  // OpenAI Realtime CHAT — issue ephemeral client_secret for conversational
  // gpt-realtime (NOT gpt-realtime-translate). Same browser↔OpenAI WebRTC
  // approach; server only mints the short-lived token. Default instructions
  // can be overridden by the client. Mirrors scripts/realtime-chat-server.js.
  app.post('/api/realtime-chat/session', async (req, res) => {
    try {
      const {
        voice = 'marin',
        instructions = '',
        inputLanguage = '',
        roomMode = false,
        vadThreshold = 0.5,
        transcriptionModel = 'gpt-4o-transcribe',
      } = req.body || {};

      if (!config.openaiRealtimeChat.apiKey) {
        return res.status(500).json({ error: 'OPENAI_API_KEY is not configured' });
      }

      const noiseReduction = roomMode ? null : { type: 'near_field' };
      const threshold = Math.max(0, Math.min(1, Number(vadThreshold) || 0.5));

      const body = {
        session: {
          type: 'realtime',
          model: config.openaiRealtimeChat.model,
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

      const r = await fetch(config.openaiRealtimeChat.clientSecretUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${config.openaiRealtimeChat.apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });

      if (!r.ok) {
        const errText = await r.text();
        logger.error(`[Realtime-Chat] client_secret ${r.status}: ${errText}`);
        return res.status(r.status).json({ error: errText });
      }
      const data = await r.json();
      if (!data || typeof data.value !== 'string') {
        return res.status(502).json({ error: 'OpenAI did not return a client_secret value' });
      }
      logger.info(`[Realtime-Chat] session created (model=${config.openaiRealtimeChat.model}, voice=${voice})`);
      res.json({
        client_secret: data.value,
        expires_at: data.expires_at ?? null,
        model: config.openaiRealtimeChat.model,
      });
    } catch (e) {
      logger.error('[Realtime-Chat] session error:', e);
      res.status(500).json({ error: e.message });
    }
  });

  // Text-to-Speech via ElevenLabs
  app.post('/api/tts', async (req, res) => {
    try {
      const { text, language } = req.body;
      if (!text) {
        return res.status(400).json({ error: 'Missing required field: text' });
      }

      const audioBuffer = await elevenLabsService.textToSpeech(text, language);
      res.set('Content-Type', 'audio/mpeg');
      res.set('Content-Length', audioBuffer.length);
      res.send(audioBuffer);
    } catch (error) {
      logger.error('Error in TTS:', error);
      res.status(500).json({ error: 'TTS failed' });
    }
  });

  // Debug logging from Mini App frontend
  app.post('/api/debug', (req, res) => {
    const { tag, data } = req.body;
    logger.info(`[WEBAPP ${tag || 'DBG'}] ${JSON.stringify(data)}`);
    res.json({ ok: true });
  });

  // Get user language config
  app.get('/api/user/:telegramId', async (req, res) => {
    try {
      const telegramId = parseInt(req.params.telegramId);
      const user = await databaseService.getUserByTelegramId(telegramId);
      if (!user) {
        return res.status(404).json({ error: 'User not found' });
      }

      res.json({
        primaryLanguage: user.languages.primaryLanguage,
        secondaryLanguage: user.languages.secondaryLanguage,
        languages: config.languages,
        sttProvider: config.stt.provider
      });
    } catch (error) {
      logger.error('Error fetching user:', error);
      res.status(500).json({ error: 'Failed to fetch user' });
    }
  });

  // Update user language preferences
  app.put('/api/user/:telegramId/languages', async (req, res) => {
    try {
      const telegramId = parseInt(req.params.telegramId);
      const { primaryLanguage, secondaryLanguage } = req.body;

      if (!primaryLanguage || !secondaryLanguage) {
        return res.status(400).json({ error: 'Missing primaryLanguage or secondaryLanguage' });
      }
      if (!config.languages[primaryLanguage] || !config.languages[secondaryLanguage]) {
        return res.status(400).json({ error: 'Unsupported language code' });
      }
      if (primaryLanguage === secondaryLanguage) {
        return res.status(400).json({ error: 'Languages must be different' });
      }

      const user = await databaseService.getUserByTelegramId(telegramId);
      if (!user) {
        return res.status(404).json({ error: 'User not found' });
      }

      await databaseService.updateUserLanguages(user._id, primaryLanguage, secondaryLanguage);
      res.json({ primaryLanguage, secondaryLanguage });
    } catch (error) {
      logger.error('Error updating user languages:', error);
      res.status(500).json({ error: 'Failed to update languages' });
    }
  });

  return app;
}

/**
 * Persistent WebSocket proxy to ElevenLabs Flash v2.5 (PCM 24kHz).
 *
 * Client → server protocol (one ElevenLabs WS per logical session):
 *   { type: 'init',  language: 'uk' }   → backend opens upstream WS + sends BOS
 *   { type: 'chunk', text: '<delta>' }  → backend sends { text: delta+' ', flush:true }
 *   { type: 'end' }                     → backend sends EOS { text:'' } and closes upstream
 *
 * Server → client:
 *   binary PCM frames as audio chunks arrive
 *   { type: 'first-byte', latencyMs: N } once per chunk burst (resets after each chunk)
 *   { type: 'error',  message }
 *   { type: 'done' }                    upstream close acknowledged
 */
function attachTtsWsProxy() {
  // Caller routes /ws/tts upgrades into this WSS via handleUpgrade().
  const wss = new WebSocket.Server({ noServer: true });

  wss.on('connection', (clientWs) => {
    logger.info('[TTS-WS] Client connected');
    let upstream = null;        // { ws, ready, pending: [], language, chunkStartTs, firstByteSent }
    let language = 'uk';
    let voiceSpeed = 1.0;       // 0.7–1.2 per ElevenLabs Flash v2.5

    function openUpstream() {
      const voiceId = config.elevenLabs.ttsVoice;
      const url = `wss://api.elevenlabs.io/v1/text-to-speech/${voiceId}/stream-input`
        + `?model_id=eleven_flash_v2_5`
        + `&output_format=pcm_24000`
        + `&language_code=${language}`
        + `&inactivity_timeout=180`;

      const ws = new WebSocket(url, {
        headers: { 'xi-api-key': config.elevenLabs.apiKey },
      });
      const session = { ws, ready: false, pending: [], language, chunkStartTs: 0, firstByteSent: false };
      upstream = session;

      ws.on('open', () => {
        if (upstream !== session) { try { ws.close(); } catch {} return; } // superseded
        logger.info(`[TTS-WS] Upstream open (lang=${language}, speed=${voiceSpeed})`);
        try {
          ws.send(JSON.stringify({
            text: ' ',
            voice_settings: { stability: 0.5, similarity_boost: 0.8, speed: voiceSpeed },
          }));
        } catch (e) { logger.error('[TTS-WS] BOS send failed:', e.message); return; }
        session.ready = true;
        // Flush any chunks that arrived during connect
        for (const text of session.pending) sendChunkToUpstream(session, text);
        session.pending = [];
      });

      ws.on('message', (data) => {
        if (upstream !== session) return;
        let payload;
        try { payload = JSON.parse(data.toString()); } catch (e) {
          logger.error('[TTS-WS] Upstream parse error:', e.message);
          return;
        }
        if (payload.audio) {
          const buf = Buffer.from(payload.audio, 'base64');
          if (!session.firstByteSent && session.chunkStartTs) {
            const tFirst = Date.now() - session.chunkStartTs;
            try { clientWs.send(JSON.stringify({ type: 'first-byte', latencyMs: tFirst })); } catch {}
            session.firstByteSent = true;
            logger.info(`[TTS-WS] First audio byte in ${tFirst}ms`);
          }
          try { clientWs.send(buf, { binary: true }); } catch {}
        }
      });

      ws.on('error', (err) => {
        if (upstream !== session) return;
        logger.error('[TTS-WS] Upstream error:', err.message);
        try { clientWs.send(JSON.stringify({ type: 'error', message: err.message })); } catch {}
      });

      ws.on('close', () => {
        logger.info('[TTS-WS] Upstream closed');
        if (upstream === session) {
          try { clientWs.send(JSON.stringify({ type: 'done' })); } catch {}
          upstream = null;
        }
      });
    }

    function sendChunkToUpstream(session, text) {
      session.chunkStartTs = Date.now();
      session.firstByteSent = false;
      try {
        session.ws.send(JSON.stringify({ text: text + ' ', flush: true }));
      } catch (e) {
        logger.error('[TTS-WS] chunk send failed:', e.message);
      }
    }

    clientWs.on('message', (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); } catch { return; }

      if (msg.type === 'init') {
        language = msg.language || 'uk';
        const reqSpeed = Number(msg.speed);
        voiceSpeed = Number.isFinite(reqSpeed) ? Math.min(Math.max(reqSpeed, 0.7), 1.2) : 1.0;
        if (upstream && upstream.ws && upstream.ws.readyState === WebSocket.OPEN) {
          try { upstream.ws.close(); } catch {}
        }
        upstream = null;
        openUpstream();
        return;
      }

      if (msg.type === 'chunk') {
        const text = (msg.text || '').trim();
        if (!text) return;
        if (!upstream) {
          logger.warn('[TTS-WS] chunk received without init — opening upstream');
          openUpstream();
          upstream.pending.push(text);
          return;
        }
        if (!upstream.ready) {
          // Still connecting — queue, will flush on 'open'
          upstream.pending.push(text);
          return;
        }
        sendChunkToUpstream(upstream, text);
        return;
      }

      if (msg.type === 'end') {
        if (upstream && upstream.ready) {
          try { upstream.ws.send(JSON.stringify({ text: '' })); } catch {}
        }
        return;
      }
    });

    clientWs.on('close', () => {
      logger.info('[TTS-WS] Client disconnected');
      if (upstream && upstream.ws) {
        try { if (upstream.ready) upstream.ws.send(JSON.stringify({ text: '' })); } catch {}
        try { upstream.ws.close(); } catch {}
      }
      upstream = null;
    });
  });

  return wss;
}

function startServer() {
  const app = createServer();
  const port = config.server.port;
  const httpServer = http.createServer(app);

  // Two WS endpoints share one HTTP server. Use `noServer:true` and route upgrades
  // by URL — multiple `WebSocket.Server({ server, path })` instances would conflict
  // (the first listener destroys upgrades for paths it doesn't recognize).
  const wssTts = attachTtsWsProxy();
  const wssLive = attachLiveWs({
    groqApiKey:         config.groq.apiKey,
    sonioxApiKey:       config.soniox.apiKey,
    sonioxTtsApiKey:    config.soniox.ttsApiKey,
    sonioxTtsVoice:     config.soniox.ttsVoice,
    elevenApiKey:       config.elevenLabs.apiKey,
    elevenVoiceId:      config.elevenLabs.ttsVoice,
    defaultTtsProvider: config.liveTranslator.ttsProvider,
    logger,
  });

  httpServer.on('upgrade', (req, socket, head) => {
    const url = req.url || '';
    if (url === '/ws/tts' || url.startsWith('/ws/tts?')) {
      wssTts.handleUpgrade(req, socket, head, (ws) => wssTts.emit('connection', ws, req));
    } else if (url === '/ws/live' || url.startsWith('/ws/live?')) {
      wssLive.handleUpgrade(req, socket, head, (ws) => wssLive.emit('connection', ws, req));
    } else {
      socket.destroy();
    }
  });

  httpServer.listen(port, () => {
    logger.info(`🌐 Express server running on port ${port}`);
    logger.info(`📱 Mini App: ${config.server.webappUrl}/webapp/index.html`);
    logger.info(`⚡ Live translator: ${config.server.webappUrl}/webapp/live.html`);
    logger.info(`🌍 Palabra demo:   ${config.server.webappUrl}/webapp/palabra.html`);
    logger.info(`🤖 OpenAI Realtime: ${config.server.webappUrl}/webapp/realtime.html`);
    logger.info(`🔌 TTS WS proxy: /ws/tts`);
    logger.info(`🚀 Live engine WS: /ws/live`);
  });
  return app;
}

module.exports = { createServer, startServer };
