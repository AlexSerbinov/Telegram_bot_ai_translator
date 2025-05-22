const mongoose = require('mongoose');

const translationSchema = new mongoose.Schema({
  original: {
    text: {
      type: String,
      required: true
    },
    language: {
      type: String,
      required: true,
      enum: ['uk', 'en', 'ka', 'id', 'ru']
    }
  },
  translated: {
    text: {
      type: String,
      required: true
    },
    language: {
      type: String,
      required: true,
      enum: ['uk', 'en', 'ka', 'id', 'ru']
    }
  },
  backTranslation: {
    type: String,
    required: true
  },
  tokensUsed: {
    type: Number,
    default: 0
  },
  audioFile: {
    telegramFileId: String,
    duration: Number,
    size: Number
  },
  ttsGenerated: {
    type: Boolean,
    default: false
  }
}, {
  timestamps: true
});

const chatSchema = new mongoose.Schema({
  user: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
    index: true
  },
  title: {
    type: String,
    required: true,
    maxlength: 100
  },
  description: {
    type: String,
    maxlength: 500
  },
  
  // Languages used in this chat
  languagePair: {
    from: {
      type: String,
      required: true,
      enum: ['uk', 'en', 'ka', 'id', 'ru']
    },
    to: {
      type: String,
      required: true,
      enum: ['uk', 'en', 'ka', 'id', 'ru']
    }
  },
  
  // Chat status
  status: {
    type: String,
    enum: ['active', 'archived', 'deleted'],
    default: 'active'
  },
  
  // Translations in this chat
  translations: [translationSchema],
  
  // Chat statistics
  stats: {
    totalTranslations: {
      type: Number,
      default: 0
    },
    totalTokensUsed: {
      type: Number,
      default: 0
    },
    avgTranslationTime: {
      type: Number,
      default: 0
    },
    lastActivity: {
      type: Date,
      default: Date.now
    }
  },
  
  // Settings specific to this chat
  settings: {
    autoTTS: {
      type: Boolean,
      default: false
    },
    saveAudio: {
      type: Boolean,
      default: false
    }
  }
}, {
  timestamps: true
});

// Indexes for performance
chatSchema.index({ user: 1, status: 1 });
chatSchema.index({ 'stats.lastActivity': -1 });
chatSchema.index({ createdAt: -1 });

// Virtual for translations count
chatSchema.virtual('translationsCount').get(function() {
  return this.translations.length;
});

// Method to add translation
chatSchema.methods.addTranslation = function(translationData) {
  this.translations.push(translationData);
  this.stats.totalTranslations += 1;
  this.stats.totalTokensUsed += translationData.tokensUsed || 0;
  this.stats.lastActivity = new Date();
  
  // Update language pair if different
  if (this.languagePair.from !== translationData.original.language ||
      this.languagePair.to !== translationData.translated.language) {
    this.languagePair = {
      from: translationData.original.language,
      to: translationData.translated.language
    };
  }
  
  return this.save();
};

// Method to update title based on first translation
chatSchema.methods.updateTitleFromTranslation = function() {
  if (this.translations.length > 0 && this.title === 'Новий чат') {
    const firstTranslation = this.translations[0];
    // Take first 50 characters of original text as title
    this.title = firstTranslation.original.text.substring(0, 50) + 
                 (firstTranslation.original.text.length > 50 ? '...' : '');
  }
};

// Static method to create new chat for user
chatSchema.statics.createForUser = async function(userId, languagePair) {
  const chat = new this({
    user: userId,
    title: 'Новий чат',
    languagePair: languagePair
  });
  
  return await chat.save();
};

// Static method to get user's active chats
chatSchema.statics.getUserActiveChats = async function(userId, limit = 10) {
  return await this.find({
    user: userId,
    status: 'active'
  })
  .sort({ 'stats.lastActivity': -1 })
  .limit(limit)
  .select('title languagePair stats.totalTranslations stats.lastActivity createdAt');
};

// Static method to get chat with translations
chatSchema.statics.getChatWithTranslations = async function(chatId, limit = 20) {
  return await this.findById(chatId)
    .populate('user', 'telegramId firstName')
    .slice('translations', -limit); // Get last N translations
};

module.exports = mongoose.model('Chat', chatSchema); 