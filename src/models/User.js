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

  // User stats
  stats: {
    totalTranslations: {
      type: Number,
      default: 0
    },
    favoriteLanguagePair: {
      from: String,
      to: String
    }
  },

  // Premium features preferences
  preferences: {
    autoLanguageDetection: {
      type: Boolean,
      default: true  // Enabled by default if user has premium
    },
    backTranslation: {
      type: Boolean,
      default: true  // Enabled by default if user has premium
    }
  },

  // Temporary state for free users
  voiceState: {
    selectedInputLanguage: {
      type: String,
      enum: ['uk', 'en', 'ka', 'id', 'ru'],
      required: false
    },
    isWaitingForVoice: {
      type: Boolean,
      default: false
    },
    stateExpires: {
      type: Date,
      required: false
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
  
  // Get limits based on subscription type
  const dailyLimit = this.isPremium ? tokenLimits.premiumTierDaily : tokenLimits.freeTierDaily;
  const monthlyLimit = this.isPremium ? tokenLimits.premiumTierMonthly : tokenLimits.freeTierMonthly;
  
  return (this.tokenUsage.dailyUsed + estimatedTokens) <= dailyLimit &&
         (this.tokenUsage.monthlyUsed + estimatedTokens) <= monthlyLimit;
};

// Method to add token usage
userSchema.methods.addTokenUsage = function(tokens) {
  this.tokenUsage.dailyUsed += tokens;
  this.tokenUsage.monthlyUsed += tokens;
  this.tokenUsage.totalUsed += tokens;
};

// Method to check if user has premium feature access
userSchema.methods.hasPremiumFeature = function(featureName) {
  if (!this.isPremium) {
    return false;
  }
  
  const { premium } = require('../config/config').config;
  return premium.features[featureName] === true;
};

// Method to get user's current limits
userSchema.methods.getCurrentLimits = function() {
  const { tokenLimits } = require('../config/config').config;
  
  if (this.isPremium) {
    return {
      dailyLimit: tokenLimits.premiumTierDaily,
      monthlyLimit: tokenLimits.premiumTierMonthly,
      dailyUsed: this.tokenUsage.dailyUsed,
      monthlyUsed: this.tokenUsage.monthlyUsed,
      type: 'premium'
    };
  } else {
    return {
      dailyLimit: tokenLimits.freeTierDaily,
      monthlyLimit: tokenLimits.freeTierMonthly,
      dailyUsed: this.tokenUsage.dailyUsed,
      monthlyUsed: this.tokenUsage.monthlyUsed,
      type: 'free'
    };
  }
};

// Method to set voice input language for free users
userSchema.methods.setVoiceInputLanguage = function(languageCode) {
  this.voiceState.selectedInputLanguage = languageCode;
  this.voiceState.isWaitingForVoice = true;
  this.voiceState.stateExpires = new Date(Date.now() + 5 * 60 * 1000); // 5 minutes
};

// Method to check if user is waiting for voice and hasn't expired
userSchema.methods.isWaitingForVoice = function() {
  if (!this.voiceState.isWaitingForVoice) {
    return false;
  }
  
  if (this.voiceState.stateExpires && this.voiceState.stateExpires < new Date()) {
    // State expired, reset
    this.voiceState.isWaitingForVoice = false;
    this.voiceState.selectedInputLanguage = null;
    this.voiceState.stateExpires = null;
    return false;
  }
  
  return true;
};

// Method to clear voice state
userSchema.methods.clearVoiceState = function() {
  this.voiceState.isWaitingForVoice = false;
  this.voiceState.selectedInputLanguage = null;
  this.voiceState.stateExpires = null;
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