const mongoose = require('mongoose');
const { config } = require('../config/config');
const logger = require('../utils/logger');

// Import models
const User = require('../models/User');

class DatabaseService {
  constructor() {
    this.isConnected = false;
  }

  /**
   * Connect to MongoDB
   */
  async connect() {
    try {
      if (this.isConnected) {
        logger.info('Database already connected');
        return;
      }

      await mongoose.connect(config.mongodb.uri, {
        useNewUrlParser: true,
        useUnifiedTopology: true,
        maxPoolSize: 10,
        serverSelectionTimeoutMS: 5000,
        socketTimeoutMS: 45000,
      });

      this.isConnected = true;
      logger.info('✅ Connected to MongoDB successfully');

      // Set up connection event listeners
      mongoose.connection.on('error', (error) => {
        logger.error('MongoDB connection error:', error);
        this.isConnected = false;
      });

      mongoose.connection.on('disconnected', () => {
        logger.warn('MongoDB disconnected');
        this.isConnected = false;
      });

      mongoose.connection.on('reconnected', () => {
        logger.info('MongoDB reconnected');
        this.isConnected = true;
      });

    } catch (error) {
      logger.error('Failed to connect to MongoDB:', error);
      throw error;
    }
  }

  /**
   * Disconnect from MongoDB
   */
  async disconnect() {
    try {
      if (this.isConnected) {
        await mongoose.disconnect();
        this.isConnected = false;
        logger.info('Disconnected from MongoDB');
      }
    } catch (error) {
      logger.error('Error disconnecting from MongoDB:', error);
      throw error;
    }
  }

  /**
   * Check connection status
   */
  isConnectionHealthy() {
    return this.isConnected && mongoose.connection.readyState === 1;
  }

  // User-related methods
  
  /**
   * Find or create user from Telegram data
   */
  async findOrCreateUser(telegramUser) {
    try {
      return await User.findOrCreate(telegramUser);
    } catch (error) {
      logger.error('Error finding/creating user:', error);
      throw error;
    }
  }

  /**
   * Get user by Telegram ID
   */
  async getUserByTelegramId(telegramId) {
    try {
      return await User.findOne({ telegramId });
    } catch (error) {
      logger.error('Error getting user by Telegram ID:', error);
      throw error;
    }
  }

  /**
   * Update user language preferences
   */
  async updateUserLanguages(userId, primaryLanguage, secondaryLanguage) {
    try {
      return await User.findByIdAndUpdate(
        userId,
        {
          'languages.primaryLanguage': primaryLanguage,
          'languages.secondaryLanguage': secondaryLanguage
        },
        { new: true }
      );
    } catch (error) {
      logger.error('Error updating user languages:', error);
      throw error;
    }
  }

  /**
   * Add token usage to user
   */
  async addUserTokenUsage(userId, tokens) {
    try {
      const user = await User.findById(userId);
      if (user) {
        user.addTokenUsage(tokens);
        await user.save();
      }
      return user;
    } catch (error) {
      logger.error('Error adding token usage:', error);
      throw error;
    }
  }

  /**
   * Check if user can make translation
   */
  async canUserMakeTranslation(userId, estimatedTokens = 100) {
    try {
      const user = await User.findById(userId);
      return user ? user.canMakeTranslation(estimatedTokens) : false;
    } catch (error) {
      logger.error('Error checking user translation limits:', error);
      return false;
    }
  }

  /**
   * Increment user translation count
   */
  async incrementUserTranslations(userId) {
    try {
      return await User.findByIdAndUpdate(
        userId,
        { $inc: { 'stats.totalTranslations': 1 } },
        { new: true }
      );
    } catch (error) {
      logger.error('Error incrementing user translations:', error);
      throw error;
    }
  }



  // Analytics and stats methods

  /**
   * Get user statistics
   */
  async getUserStats(userId) {
    try {
      const user = await User.findById(userId).select('stats tokenUsage subscription');
      return user;
    } catch (error) {
      logger.error('Error getting user stats:', error);
      throw error;
    }
  }

  /**
   * Get global statistics (for admin)
   */
  async getGlobalStats() {
    try {
      const [totalUsers, totalTranslations] = await Promise.all([
        User.countDocuments(),
        User.aggregate([
          { $group: { _id: null, total: { $sum: '$stats.totalTranslations' } } }
        ])
      ]);

      return {
        totalUsers,
        totalTranslations: totalTranslations[0]?.total || 0
      };
    } catch (error) {
      logger.error('Error getting global stats:', error);
      throw error;
    }
  }
}

module.exports = new DatabaseService(); 