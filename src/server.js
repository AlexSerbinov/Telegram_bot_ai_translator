const express = require('express');
const path = require('path');
const { config } = require('./config/config');
const logger = require('./utils/logger');
const elevenLabsService = require('./services/elevenLabsService');
const geminiService = require('./services/geminiService');
const groqService = require('./services/groqService');
const databaseService = require('./services/databaseService');

function createServer() {
  const app = express();
  app.use(express.json());

  // Serve Mini App static files
  app.use('/webapp', express.static(path.join(__dirname, 'webapp')));

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

function startServer() {
  const app = createServer();
  const port = config.server.port;
  app.listen(port, () => {
    logger.info(`🌐 Express server running on port ${port}`);
    logger.info(`📱 Mini App: ${config.server.webappUrl}/webapp/index.html`);
  });
  return app;
}

module.exports = { createServer, startServer };
