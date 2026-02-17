require('dotenv').config();

const config = {
  // Telegram Bot Configuration
  telegram: {
    token: process.env.TELEGRAM_BOT_TOKEN,
  },

  // OpenAI Configuration
  openai: {
    apiKey: process.env.OPENAI_API_KEY,
    models: {
      gpt: 'gpt-4o-mini',
      tts: 'tts-1'
    }
  },

  // ElevenLabs Configuration
  elevenLabs: {
    apiKey: process.env.ELEVEN_LABS_API_KEY,
    models: {
      stt: 'scribe_v2',
      tts: 'eleven_multilingual_v2'
    },
    ttsVoice: process.env.ELEVEN_LABS_TTS_VOICE || 'FFHOCNsj5TuX6tRgEswC' // Adam (deep male)
  },

  // Real-time STT provider for Mini App: 'soniox' | 'elevenlabs'
  stt: {
    provider: process.env.STT_PROVIDER || 'soniox'
  },

  // Soniox Configuration (Real-time STT in Mini App)
  soniox: {
    apiKey: process.env.SONIOX_API_KEY,
    model: 'stt-rt-preview'
  },

  // Google Gemini Configuration
  gemini: {
    apiKey: process.env.GOOGLE_GEMINI_API_KEY,
    model: 'gemini-3-flash-preview'
  },

  // Server Configuration (Express for Mini App)
  server: {
    port: parseInt(process.env.SERVER_PORT) || 3000,
    webappUrl: process.env.WEBAPP_URL || 'http://localhost:3000'
  },

  // Bot Configuration
  bot: {
    environment: process.env.NODE_ENV || 'development',
    logLevel: process.env.LOG_LEVEL || 'info',
    tempAudioDir: process.env.TEMP_AUDIO_DIR || './temp/audio',
    maxAudioSize: process.env.MAX_AUDIO_SIZE || '50MB'
  },

  // Supported Languages
  languages: {
    uk: { name: 'Українська', nameUk: 'Українська', flag: '🇺🇦', openaiCode: 'uk' },
    en: { name: 'English', nameUk: 'Англійська', flag: '🇺🇸', openaiCode: 'en' },
    es: { name: 'Español', nameUk: 'Іспанська', flag: '🇪🇸', openaiCode: 'es' },
    ka: { name: 'ქართული', nameUk: 'Грузинська', flag: '🇬🇪', openaiCode: 'ka' },
    id: { name: 'Bahasa Indonesia', nameUk: 'Індонезійська', flag: '🇮🇩', openaiCode: 'id' },
  },

  // MongoDB Configuration
  mongodb: {
    uri: process.env.MONGODB_URI || 'mongodb://admin:secretpassword@localhost:27017/ai-translator?authSource=admin'
  },

  // Token Limits Configuration
  tokenLimits: {
    // Free tier limits
    freeTierDaily: parseInt(process.env.FREE_TIER_DAILY_TOKENS) || 10000,
    freeTierMonthly: parseInt(process.env.FREE_TIER_MONTHLY_TOKENS) || 100000,
    
    // Premium tier limits (x10 more)
    premiumTierDaily: parseInt(process.env.PREMIUM_TIER_DAILY_TOKENS) || 100000,
    premiumTierMonthly: parseInt(process.env.PREMIUM_TIER_MONTHLY_TOKENS) || 1000000
  },

  // Premium features configuration
  premium: {
    features: {
      autoLanguageDetection: true,    // Automatic language detection (free users must select manually)
      backTranslation: true,          // Back translation for verification
      advancedModels: true,           // Use GPT for language detection instead of just Whisper
      unlimitedChats: true,           // No limit on chats (if we add them back later)
      prioritySupport: true           // Priority customer support
    }
  }
};

// Validate required configuration
const validateConfig = () => {
  const required = [
    'TELEGRAM_BOT_TOKEN',
    'OPENAI_API_KEY'
  ];

  const missing = required.filter(key => !process.env[key]);
  
  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(', ')}`);
  }
};

module.exports = { config, validateConfig }; 