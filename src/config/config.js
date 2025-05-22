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
      whisper: 'whisper-1',
      gpt: 'gpt-3.5-turbo',
      tts: 'tts-1'
    }
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
    uk: { name: 'Українська', flag: '🇺🇦', openaiCode: 'uk' },
    en: { name: 'English', flag: '🇺🇸', openaiCode: 'en' },
    ka: { name: 'ქართული', flag: '🇬🇪', openaiCode: 'ka' },
    id: { name: 'Bahasa Indonesia', flag: '🇮🇩', openaiCode: 'id' },
    ru: { name: 'Русский', flag: '🇷🇺', openaiCode: 'ru' }
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