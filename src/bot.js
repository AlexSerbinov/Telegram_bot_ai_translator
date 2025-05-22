const { Telegraf } = require('telegraf');
const { config, validateConfig } = require('./config/config');
const logger = require('./utils/logger');
const fs = require('fs-extra');

// Import services
const databaseService = require('./services/databaseService');

// Import handlers
const commandHandlers = require('./handlers/commandHandlers');
const callbackHandlers = require('./handlers/callbackHandlers');
const audioHandler = require('./handlers/audioHandler');

class AITranslatorBot {
  constructor() {
    // Validate configuration
    validateConfig();
    
    // Initialize bot
    this.bot = new Telegraf(config.telegram.token);
    
    // Setup middleware
    this.setupMiddleware();
    
    // Setup handlers
    this.setupHandlers();
    
    // Setup error handling
    this.setupErrorHandling();
  }

  /**
   * Setup middleware
   */
  setupMiddleware() {
    // Logging middleware
    this.bot.use(async (ctx, next) => {
      const start = Date.now();
      await next();
      const ms = Date.now() - start;
      logger.info(`${ctx.updateType} - ${ms}ms`);
    });

    // User creation middleware
    this.bot.use(async (ctx, next) => {
      if (ctx.from) {
        try {
          await databaseService.findOrCreateUser(ctx.from);
        } catch (error) {
          logger.error('Error creating/finding user:', error);
        }
      }
      await next();
    });

    // Rate limiting middleware (simple implementation)
    const userRequests = new Map();
    this.bot.use(async (ctx, next) => {
      const userId = ctx.from?.id;
      if (userId) {
        const now = Date.now();
        const userRequestLog = userRequests.get(userId) || [];
        
        // Remove old requests (older than 1 minute)
        const recentRequests = userRequestLog.filter(time => now - time < 60000);
        
        if (recentRequests.length >= 20) { // Max 20 requests per minute
          logger.warn(`Rate limit exceeded for user ${userId}`);
          await ctx.reply('⚠️ Забагато запитів. Спробуйте через хвилину.');
          return;
        }
        
        recentRequests.push(now);
        userRequests.set(userId, recentRequests);
      }
      
      await next();
    });
  }

  /**
   * Setup command and callback handlers
   */
  setupHandlers() {
    // Command handlers
    this.bot.start(commandHandlers.handleStart.bind(commandHandlers));
    this.bot.command('settings', commandHandlers.handleSettings.bind(commandHandlers));
    this.bot.command('menu', commandHandlers.handleMenu.bind(commandHandlers));
    this.bot.command('stats', commandHandlers.handleStats.bind(commandHandlers));
    this.bot.command('limits', commandHandlers.handleLimits.bind(commandHandlers));
    this.bot.command('help', commandHandlers.handleHelp.bind(commandHandlers));

    // Audio handlers
    this.bot.on('voice', audioHandler.handleVoice.bind(audioHandler));
    this.bot.on('audio', audioHandler.handleAudio.bind(audioHandler));
    this.bot.on('document', audioHandler.handleDocument.bind(audioHandler));

    // Callback query handler
    this.bot.on('callback_query', callbackHandlers.handleCallback.bind(callbackHandlers));

    // Text message handler (for unknown commands)
    this.bot.on('text', commandHandlers.handleUnknownText.bind(commandHandlers));
  }

  /**
   * Setup error handling
   */
  setupErrorHandling() {
    this.bot.catch((err, ctx) => {
      logger.error('Bot error:', err);
      ctx.reply('❌ Виникла помилка. Спробуйте ще раз.');
    });

    // Handle process signals
    process.once('SIGINT', () => this.shutdown('SIGINT'));
    process.once('SIGTERM', () => this.shutdown('SIGTERM'));
  }

  /**
   * Start the bot
   */
  async start() {
    try {
      // Connect to database
      await databaseService.connect();
      
      // Ensure temp directory exists
      await fs.ensureDir(config.bot.tempAudioDir);
      
      // Start bot
      await this.bot.launch();
      
      logger.info('🤖 AI Translator Bot started successfully!');
      logger.info(`Environment: ${config.bot.environment}`);
      logger.info(`Temp audio directory: ${config.bot.tempAudioDir}`);
      
    } catch (error) {
      logger.error('Failed to start bot:', error);
      process.exit(1);
    }
  }

  /**
   * Graceful shutdown
   */
  async shutdown(signal) {
    logger.info(`Received ${signal}. Shutting down gracefully...`);
    
    try {
      // Stop bot
      this.bot.stop(signal);
      
      // Disconnect from database
      await databaseService.disconnect();
      
      logger.info('✅ Bot stopped successfully');
      process.exit(0);
    } catch (error) {
      logger.error('Error during shutdown:', error);
      process.exit(1);
    }
  }
}

// Create and start bot
const bot = new AITranslatorBot();
bot.start();

// Export for testing purposes
module.exports = { AITranslatorBot }; 