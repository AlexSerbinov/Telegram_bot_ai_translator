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
const { SonioxTtsSession, SAMPLE_RATE: SONIOX_TTS_SR } = require('./liveTranslator/ttsSoniox');
const { verifyAppleIdentityToken, issueAppJWT } = require('./services/appleAuthService');
const { requireAuth } = require('./middleware/auth');
const User = require('./models/User');

// Extended language map for the live translator demo — broader than config.languages
// (which is only the 6 languages exposed in the Telegram bot UI).
const LANG_NAMES = {
  es: 'Spanish', en: 'English', ru: 'Russian', uk: 'Ukrainian',
  de: 'German', fr: 'French', it: 'Italian', pt: 'Portuguese',
  pl: 'Polish', tr: 'Turkish', nl: 'Dutch', cs: 'Czech',
  ja: 'Japanese', zh: 'Chinese', ar: 'Arabic',
};

// One-shot Soniox TTS: opens a WS sub-stream, collects PCM s16le frames,
// returns a finished WAV buffer. Used by POST /api/tts when the iOS Phrase
// tab selects Soniox as the TTS provider.
async function synthesizeSonioxWav({ text, language }) {
  const session = new SonioxTtsSession({
    apiKey: config.soniox.ttsApiKey,
    model: config.soniox.ttsModel,
    voice: config.soniox.ttsVoice,
    language,
  });

  await session.open();

  const pcmChunks = [];
  let settled = false;

  return await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      if (settled) return;
      settled = true;
      try { session.close(); } catch {}
      reject(new Error('Soniox TTS timeout (20s)'));
    }, 20_000);

    const finish = (err) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      try { session.close(); } catch {}
      if (err) return reject(err);
      const pcm = Buffer.concat(pcmChunks);
      resolve(pcmToWav(pcm, SONIOX_TTS_SR));
    };

    session.on('audio', (buf) => pcmChunks.push(buf));
    session.on('error', (e) => finish(new Error(e?.message || 'Soniox TTS error')));
    // Resolve on close — Soniox sends `terminated:true` per sub-stream which
    // triggers a queue drain; with no further chunks, the session goes idle.
    // We wait a short tail after the last audio frame before closing ourselves.
    session.on('closed', () => finish(null));

    session.chunk(text);

    // After queuing the single chunk, close once it drains. Poll until the
    // active sub-stream finishes — `terminated:true` fires `_drain()` and
    // `activeStreamId` returns to null, queue is empty → safe to close.
    const poll = setInterval(() => {
      if (settled) { clearInterval(poll); return; }
      if (session.activeStreamId == null && session.queue.length === 0 && pcmChunks.length > 0) {
        clearInterval(poll);
        // Give the WS a beat to flush any tail frame before we close.
        setTimeout(() => finish(null), 50);
      }
    }, 50);
  });
}

// Build a 44-byte WAV header + PCM body. PCM is signed 16-bit little-endian, mono.
function pcmToWav(pcm, sampleRate) {
  const numChannels = 1;
  const bitsPerSample = 16;
  const byteRate = sampleRate * numChannels * bitsPerSample / 8;
  const blockAlign = numChannels * bitsPerSample / 8;
  const dataSize = pcm.length;
  const header = Buffer.alloc(44);
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + dataSize, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);              // PCM fmt chunk size
  header.writeUInt16LE(1, 20);               // audio format = PCM
  header.writeUInt16LE(numChannels, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(byteRate, 28);
  header.writeUInt16LE(blockAlign, 32);
  header.writeUInt16LE(bitsPerSample, 34);
  header.write('data', 36);
  header.writeUInt32LE(dataSize, 40);
  return Buffer.concat([header, pcm]);
}

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
                // Try near_field — cookbook used null but mobile mic might benefit.
                // turn_detection is NOT supported by the Translation API (returns
                // 400 unknown_parameter) — that's a regular Realtime feature only.
                noise_reduction: { type: 'near_field' },
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

  // OpenAI Realtime voice monitor — conversational gpt-realtime-2 session
  // with input transcription events enabled. The visible transcript is produced
  // by the configured ASR attachment; the voice model still consumes the
  // original audio directly.
  app.post('/api/realtime-transcription/session', async (req, res) => {
    try {
      const {
        voice = 'marin',
        instructions = '',
        inputLanguage = '',
        roomMode = false,
        vadThreshold = 0.5,
        includeLogprobs = true,
      } = req.body || {};

      if (!config.openaiRealtimeVoice.apiKey) {
        return res.status(500).json({ error: 'OPENAI_API_KEY is not configured' });
      }

      const noiseReduction = roomMode ? null : { type: 'near_field' };
      const threshold = Math.max(0, Math.min(1, Number(vadThreshold) || 0.5));

      const body = {
        session: {
          type: 'realtime',
          model: config.openaiRealtimeVoice.model,
          audio: {
            input: {
              transcription: {
                model: config.openaiRealtimeVoice.transcriptionModel,
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
          include: includeLogprobs ? ['item.input_audio_transcription.logprobs'] : [],
          tracing: 'auto',
          ...(instructions ? { instructions } : {}),
        },
      };

      const r = await fetch(config.openaiRealtimeVoice.clientSecretUrl, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${config.openaiRealtimeVoice.apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });

      if (!r.ok) {
        const errText = await r.text();
        logger.error(`[Realtime-Transcription] client_secret ${r.status}: ${errText}`);
        return res.status(r.status).json({ error: errText });
      }
      const data = await r.json();
      if (!data || typeof data.value !== 'string') {
        return res.status(502).json({ error: 'OpenAI did not return a client_secret value' });
      }
      logger.info(`[Realtime-Transcription] session created (model=${config.openaiRealtimeVoice.model}, transcription=${config.openaiRealtimeVoice.transcriptionModel}, voice=${voice})`);
      res.json({
        client_secret: data.value,
        expires_at: data.expires_at ?? null,
        model: config.openaiRealtimeVoice.model,
        transcriptionModel: config.openaiRealtimeVoice.transcriptionModel,
      });
    } catch (e) {
      logger.error('[Realtime-Transcription] session error:', e);
      res.status(500).json({ error: e.message });
    }
  });

  // Text-to-Speech — provider selectable per-request.
  //   provider = "elevenlabs" (default) → MP3 via ElevenLabs Turbo v2.5
  //   provider = "soniox"               → WAV (PCM s16le 24kHz mono) via Soniox TTS WS
  // iOS Phrase tab exposes this switch in its settings sheet.
  app.post('/api/tts', async (req, res) => {
    try {
      const { text, language, provider: rawProvider } = req.body;
      if (!text) {
        return res.status(400).json({ error: 'Missing required field: text' });
      }

      const provider = (rawProvider || 'elevenlabs').toString().toLowerCase();

      if (provider === 'soniox') {
        if (!config.soniox.ttsApiKey) {
          return res.status(500).json({ error: 'Soniox TTS not configured (SONIOX_API_KEY/SONIOX_TTS_API_KEY missing)' });
        }
        const wav = await synthesizeSonioxWav({ text, language: language || 'en' });
        res.set('Content-Type', 'audio/wav');
        res.set('Content-Length', wav.length);
        return res.send(wav);
      }

      // Default: ElevenLabs MP3
      const audioBuffer = await elevenLabsService.textToSpeech(text, language);
      res.set('Content-Type', 'audio/mpeg');
      res.set('Content-Length', audioBuffer.length);
      res.send(audioBuffer);
    } catch (error) {
      logger.error('Error in TTS:', error);
      res.status(500).json({ error: 'TTS failed', message: error?.message || String(error) });
    }
  });

  // Debug logging from Mini App frontend
  app.post('/api/debug', (req, res) => {
    const { tag, data } = req.body;
    logger.info(`[WEBAPP ${tag || 'DBG'}] ${JSON.stringify(data)}`);
    res.json({ ok: true });
  });

  // --- iOS / Mini App remote log shipping ------------------------------
  //
  // The iOS app's `DiagLogger` ring buffer is only visible inside the app's
  // own Log panel. To let a developer (or an AI agent) debug live flows
  // without screen-sharing the phone, the client batches its entries and
  // POSTs them here every couple of seconds. We keep a small server-side
  // ring buffer (5k entries) and expose a `GET /api/logs?limit=…` so the
  // developer can `curl` the latest events.
  //
  // No auth: useful during dev. The endpoint MUST NOT be reused for anything
  // sensitive — anyone with the URL can read them. We strip nothing.

  const LOG_RING_MAX = 5000;
  const logRing = []; // {ts, deviceID, tag, line}
  let nextLogSeq = 1;

  app.post('/api/logs', (req, res) => {
    const { deviceID, entries } = req.body || {};
    if (!Array.isArray(entries)) {
      return res.status(400).json({ error: 'entries must be an array' });
    }
    const safeDevice = (deviceID || 'unknown').toString().slice(0, 64);
    for (const e of entries) {
      const tag = (e?.tag || 'app').toString().slice(0, 24);
      const line = (e?.line || '').toString().slice(0, 1024);
      const ts = (e?.ts || Date.now());
      logRing.push({ seq: nextLogSeq++, ts, deviceID: safeDevice, tag, line });
      if (logRing.length > LOG_RING_MAX) logRing.shift();
    }
    res.json({ ok: true, stored: entries.length, sinceSeq: nextLogSeq });
  });

  app.get('/api/logs', (req, res) => {
    const limit = Math.min(parseInt(req.query.limit, 10) || 200, LOG_RING_MAX);
    const sinceSeq = parseInt(req.query.sinceSeq, 10) || 0;
    const deviceFilter = req.query.deviceID;
    const tagFilter = req.query.tag;
    let filtered = logRing;
    if (sinceSeq > 0) filtered = filtered.filter(e => e.seq > sinceSeq);
    if (deviceFilter) filtered = filtered.filter(e => e.deviceID === deviceFilter);
    if (tagFilter) filtered = filtered.filter(e => e.tag === tagFilter);
    const slice = filtered.slice(-limit);
    res.json({ count: slice.length, entries: slice });
  });

  app.post('/api/logs/clear', (req, res) => {
    logRing.length = 0;
    res.json({ ok: true });
  });

  // --- iOS Voice Log (diarized session transcripts) ---------------------
  //
  // A "voice log" entry is one utterance attributed to either a human speaker
  // (with a Soniox-assigned speaker id) or the model. Bridge sessions stream
  // these in real time so the server can reconstruct "who said what, when"
  // for each session — and so the iOS History tab can render past sessions.
  //
  // In-memory ring, no auth, capped to last 200 sessions / 50k entries.

  const VOICE_LOG_MAX_ENTRIES = 50000;
  const VOICE_LOG_MAX_SESSIONS = 200;
  const voiceLogEntries = []; // {seq, ts, deviceID, sessionID, role, speaker, lang, text}
  let nextVoiceSeq = 1;

  app.post('/api/voice-log', (req, res) => {
    const { deviceID, sessionID, entries } = req.body || {};
    if (!sessionID || typeof sessionID !== 'string') {
      return res.status(400).json({ error: 'Missing sessionID' });
    }
    if (!Array.isArray(entries)) {
      return res.status(400).json({ error: 'entries must be an array' });
    }
    const safeDevice = (deviceID || 'unknown').toString().slice(0, 64);
    const safeSession = sessionID.toString().slice(0, 64);
    let stored = 0;
    for (const e of entries) {
      const role = ['human', 'model', 'meta'].includes(e?.role) ? e.role : 'human';
      const text = (e?.text || '').toString().slice(0, 4096);
      const speaker = e?.speaker ? e.speaker.toString().slice(0, 16) : null;
      const lang = e?.lang ? e.lang.toString().slice(0, 8) : null;
      const ts = e?.ts || Date.now();
      voiceLogEntries.push({
        seq: nextVoiceSeq++, ts, deviceID: safeDevice, sessionID: safeSession,
        role, speaker, lang, text,
      });
      stored++;
    }
    while (voiceLogEntries.length > VOICE_LOG_MAX_ENTRIES) voiceLogEntries.shift();
    res.json({ ok: true, stored, sinceSeq: nextVoiceSeq });
  });

  app.get('/api/voice-log/sessions', (req, res) => {
    const deviceFilter = req.query.deviceID;
    const limit = Math.min(parseInt(req.query.limit, 10) || 50, VOICE_LOG_MAX_SESSIONS);
    const bySession = new Map();
    for (const e of voiceLogEntries) {
      if (deviceFilter && e.deviceID !== deviceFilter) continue;
      let s = bySession.get(e.sessionID);
      if (!s) {
        s = { sessionID: e.sessionID, deviceID: e.deviceID, startedAt: e.ts, endedAt: e.ts, entryCount: 0 };
        bySession.set(e.sessionID, s);
      }
      s.endedAt = Math.max(s.endedAt, e.ts);
      s.startedAt = Math.min(s.startedAt, e.ts);
      s.entryCount += 1;
    }
    const fs = require('fs-extra');
    const path = require('path');
    const dir = path.join(__dirname, '..', 'data', 'recordings');
    const sessionsList = Array.from(bySession.values())
      .sort((a, b) => b.endedAt - a.endedAt)
      .slice(0, limit)
      .map(s => {
        const wav = path.join(dir, `${s.sessionID}.wav`);
        const hasRecording = fs.existsSync(wav);
        return { ...s, recordingFile: hasRecording ? `/api/recordings/${s.sessionID}.wav` : null };
      });
    res.json({ count: sessionsList.length, sessions: sessionsList });
  });

  app.get('/api/voice-log/sessions/:sessionID', (req, res) => {
    const { sessionID } = req.params;
    const deviceFilter = req.query.deviceID;
    const entries = voiceLogEntries.filter(e => {
      if (e.sessionID !== sessionID) return false;
      if (deviceFilter && e.deviceID !== deviceFilter) return false;
      return true;
    });
    if (entries.length === 0) return res.status(404).json({ error: 'Session not found' });
    const fs = require('fs-extra');
    const path = require('path');
    const wav = path.join(__dirname, '..', 'data', 'recordings', `${sessionID}.wav`);
    const recordingFile = fs.existsSync(wav) ? `/api/recordings/${sessionID}.wav` : null;
    res.json({
      sessionID,
      deviceID: entries[0].deviceID,
      startedAt: entries[0].ts,
      endedAt: entries[entries.length - 1].ts,
      recordingFile,
      entries: entries.map(e => ({ ts: e.ts, role: e.role, speaker: e.speaker, lang: e.lang, text: e.text })),
    });
  });

  app.post('/api/voice-log/clear', (req, res) => {
    voiceLogEntries.length = 0;
    res.json({ ok: true });
  });

  // --- iOS Recordings (WAV upload + playback for voice-log sessions) ----
  //
  // POST /api/recordings?sessionID=…&deviceID=…&label=…
  //   Body: raw WAV bytes (Content-Type: audio/wav). Saved to
  //   data/recordings/{sessionID}.wav so the voice-log endpoints can link it.
  //
  // GET /api/recordings/:filename — streams the WAV back for playback.

  app.post('/api/recordings',
    express.raw({ type: 'audio/*', limit: '50mb' }),
    async (req, res) => {
      const fs = require('fs-extra');
      const path = require('path');
      try {
        if (!req.body || !req.body.length) {
          return res.status(400).json({ error: 'Empty body' });
        }
        const sessionID = (req.query.sessionID || '').toString().slice(0, 64);
        const label = (req.query.label || 'session').toString().slice(0, 32);
        const dir = path.join(__dirname, '..', 'data', 'recordings');
        await fs.ensureDir(dir);
        const filename = sessionID
          ? `${sessionID}.wav`
          : `${label}-${Date.now()}.wav`;
        const filepath = path.join(dir, filename);
        await fs.writeFile(filepath, req.body);
        logger.info(`[Recordings] saved ${filename} (${req.body.length} bytes)`);
        res.json({ url: `/api/recordings/${filename}`, bytes: req.body.length });
      } catch (e) {
        logger.error('[Recordings] save failed:', e);
        res.status(500).json({ error: e.message });
      }
    }
  );

  app.get('/api/recordings/:filename', (req, res) => {
    const path = require('path');
    const filename = req.params.filename;
    if (!/^[A-Za-z0-9._-]+\.wav$/.test(filename)) {
      return res.status(400).json({ error: 'Invalid filename' });
    }
    const filepath = path.join(__dirname, '..', 'data', 'recordings', filename);
    res.sendFile(filepath, err => {
      if (err && !res.headersSent) res.status(404).json({ error: 'Not found' });
    });
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

  // POST /api/voice/transcribe
  // Body: raw audio bytes (Content-Type: audio/m4a, audio/wav, audio/mpeg, etc.)
  // Optional query: ?language=uk|en|es|... (default auto-detect)
  // Returns: { text, detectedLanguage, confidence }
  //
  // Used by iOS Voice tab v1 (one-shot record → batch transcription).
  // Limit 25 MB matches ElevenLabs Scribe v2 cap.
  app.post('/api/voice/transcribe',
    express.raw({ type: ['audio/*', 'application/octet-stream'], limit: '25mb' }),
    async (req, res) => {
      const fs = require('fs-extra');
      const path = require('path');
      const os = require('os');
      try {
        if (!req.body || !req.body.length) {
          return res.status(400).json({ error: 'Empty audio body' });
        }
        const ext = (req.headers['content-type'] || 'audio/m4a').split('/')[1].split(';')[0] || 'm4a';
        const tmpFile = path.join(os.tmpdir(), `voice-${Date.now()}.${ext}`);
        await fs.writeFile(tmpFile, req.body);
        try {
          const lang = (req.query.language || 'auto').toString();
          const elevenLabsService = require('./services/elevenLabsService');
          const result = await elevenLabsService.speechToText(tmpFile, lang);
          res.json(result);
        } finally {
          await fs.remove(tmpFile).catch(() => {});
        }
      } catch (error) {
        logger.error('voice transcribe failed:', error);
        res.status(500).json({ error: 'Transcription failed: ' + error.message });
      }
    }
  );

  // ── Apple Sign In ──────────────────────────────────────────────────────
  // POST /api/auth/apple
  // Body: { identityToken: string, authorizationCode?: string,
  //         fullName?: { givenName?, familyName? } }
  // Returns: { token: <app-jwt>, user: { id, email?, primaryLanguage, secondaryLanguage } }
  //
  // The iOS app gets `identityToken` from ASAuthorizationAppleIDCredential
  // and sends it here. We verify against Apple's JWKS, find/create the User
  // record, and mint a 30-day app JWT for subsequent requests.
  app.post('/api/auth/apple', async (req, res) => {
    try {
      const { identityToken, fullName } = req.body || {};
      if (!identityToken) {
        return res.status(400).json({ error: 'Missing identityToken' });
      }

      const audience = process.env.APPLE_CLIENT_ID || 'solutions.techchain.teycan.translate';
      const claims = await verifyAppleIdentityToken(identityToken, audience);

      const user = await User.findOrCreateByAppleSub({
        appleSub: claims.sub,
        email: claims.email,
        name: fullName,
      });

      const secret = process.env.JWT_SECRET;
      if (!secret) {
        logger.error('JWT_SECRET not configured');
        return res.status(500).json({ error: 'Server not configured' });
      }
      const token = await issueAppJWT(
        { userId: String(user._id), appleSub: claims.sub },
        secret
      );

      res.json({
        token,
        user: {
          id: String(user._id),
          email: user.email || null,
          primaryLanguage: user.languages?.primaryLanguage || 'uk',
          secondaryLanguage: user.languages?.secondaryLanguage || 'es',
        },
      });
    } catch (error) {
      logger.warn('Apple auth failed: ' + error.message);
      res.status(401).json({ error: 'Apple auth failed: ' + error.message });
    }
  });

  // GET /api/user/me  (JWT-protected — used by iOS)
  // Returns the authenticated user's preferences.
  app.get('/api/user/me', requireAuth(), async (req, res) => {
    const u = req.user;
    res.json({
      id: String(u._id),
      email: u.email || null,
      primaryLanguage: u.languages?.primaryLanguage || 'uk',
      secondaryLanguage: u.languages?.secondaryLanguage || 'es',
      sttProvider: process.env.STT_PROVIDER || 'soniox',
    });
  });

  // PUT /api/user/me/languages  (JWT-protected — used by iOS)
  app.put('/api/user/me/languages', requireAuth(), async (req, res) => {
    try {
      const { primaryLanguage, secondaryLanguage } = req.body || {};
      if (!primaryLanguage || !secondaryLanguage) {
        return res.status(400).json({ error: 'Missing primaryLanguage or secondaryLanguage' });
      }
      if (!config.languages[primaryLanguage] || !config.languages[secondaryLanguage]) {
        return res.status(400).json({ error: 'Unsupported language code' });
      }
      if (primaryLanguage === secondaryLanguage) {
        return res.status(400).json({ error: 'Languages must be different' });
      }
      req.user.languages = req.user.languages || {};
      req.user.languages.primaryLanguage = primaryLanguage;
      req.user.languages.secondaryLanguage = secondaryLanguage;
      await req.user.save();
      res.json({ primaryLanguage, secondaryLanguage });
    } catch (error) {
      logger.error('Error updating /me languages:', error);
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
    logger.info(`📝 Realtime transcript: ${config.server.webappUrl}/webapp/realtime-transcription.html`);
    logger.info(`🔌 TTS WS proxy: /ws/tts`);
    logger.info(`🚀 Live engine WS: /ws/live`);
  });
  return app;
}

module.exports = { createServer, startServer };
