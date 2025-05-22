const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  telegramId: {
    type: Number,
    required: true,
    unique: true,
    index: true
  },
  username: {
    type: String,
    required: false
  },
  firstName: {
    type: String,
    required: false
  },
  lastName: {
    type: String,
    required: false
  },
  
  // Language preferences - two languages for automatic detection
  languages: {
    primaryLanguage: {
      type: String,
      default: 'uk',
      enum: ['uk', 'en', 'ka', 'id', 'ru']
    },
    secondaryLanguage: {
      type: String,
      default: 'en',
      enum: ['uk', 'en', 'ka', 'id', 'ru']
    }
  },

  // Token usage tracking
  tokenUsage: {
    dailyUsed: {
      type: Number,
      default: 0
    },
    monthlyUsed: {
      type: Number,
      default: 0
    },
    lastDailyReset: {
      type: Date,
      default: Date.now
    },
    lastMonthlyReset: {
      type: Date,
      default: Date.now
    },
    totalUsed: {
      type: Number,
      default: 0
    }
  },

  // Subscription info
  subscription: {
    type: {
      type: String,
      enum: ['free', 'premium'],
      default: 'free'
    },
    expiresAt: {
      type: Date,
      required: false
    }
  },

  // Active chat
  activeChat: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Chat',
    required: false
  },

  // User stats
  stats: {
    totalTranslations: {
      type: Number,
      default: 0
    },
    totalChats: {
      type: Number,
      default: 0
    },
    favoriteLanguagePair: {
      from: String,
      to: String
    }
  }
}, {
  timestamps: true
});

// Indexes for performance
userSchema.index({ 'tokenUsage.lastDailyReset': 1 });
userSchema.index({ 'tokenUsage.lastMonthlyReset': 1 });
userSchema.index({ 'subscription.type': 1 });

// Virtual for checking if premium
userSchema.virtual('isPremium').get(function() {
  return this.subscription.type === 'premium' && 
         (!this.subscription.expiresAt || this.subscription.expiresAt > new Date());
});

// Method to check if user can make translation (token limit)
userSchema.methods.canMakeTranslation = function(estimatedTokens = 100) {
  if (this.isPremium) {
    return true;
  }
  
  // Check daily limit
  const today = new Date();
  const lastReset = new Date(this.tokenUsage.lastDailyReset);
  
  if (today.getDate() !== lastReset.getDate() || 
      today.getMonth() !== lastReset.getMonth() || 
      today.getFullYear() !== lastReset.getFullYear()) {
    // Reset daily usage
    this.tokenUsage.dailyUsed = 0;
    this.tokenUsage.lastDailyReset = today;
  }
  
  // Check monthly limit
  if (today.getMonth() !== lastReset.getMonth() || 
      today.getFullYear() !== lastReset.getFullYear()) {
    // Reset monthly usage
    this.tokenUsage.monthlyUsed = 0;
    this.tokenUsage.lastMonthlyReset = today;
  }
  
  const { tokenLimits } = require('../config/config').config;
  
  return (this.tokenUsage.dailyUsed + estimatedTokens) <= tokenLimits.freeTierDaily &&
         (this.tokenUsage.monthlyUsed + estimatedTokens) <= tokenLimits.freeTierMonthly;
};

// Method to add token usage
userSchema.methods.addTokenUsage = function(tokens) {
  this.tokenUsage.dailyUsed += tokens;
  this.tokenUsage.monthlyUsed += tokens;
  this.tokenUsage.totalUsed += tokens;
};

// Static method to find or create user
userSchema.statics.findOrCreate = async function(telegramUser) {
  let user = await this.findOne({ telegramId: telegramUser.id });
  
  if (!user) {
    user = new this({
      telegramId: telegramUser.id,
      username: telegramUser.username,
      firstName: telegramUser.first_name,
      lastName: telegramUser.last_name
    });
    await user.save();
  }
  
  return user;
};

module.exports = mongoose.model('User', userSchema); 