const languageService = require('../services/languageService');
const openaiService = require('../services/openaiService');
const databaseService = require('../services/databaseService');
const logger = require('../utils/logger');
const path = require('path');
const fs = require('fs-extra');
const axios = require('axios');
const { config } = require('../config/config');

class AudioHandler {

  /**
   * Handle voice messages
   */
  async handleVoice(ctx) {
    try {
      const userId = ctx.from.id;
      
      // Get user and settings
      const user = await databaseService.getUserByTelegramId(userId);
      if (!user) {
        await ctx.reply('❌ Помилка: користувач не знайден. Спробуйте команду /start');
        return;
      }

      const userSettings = user.languages;
      logger.info(`Processing voice message from user ${userId} (${user.isPremium ? 'Premium' : 'Free'})`);

      // Send processing message
      const processingMsg = await ctx.reply('🎤 Обробляю голосове повідомлення...\n⏳ Розпізнаю мову...');
      
      // Download audio file
      const audioPath = await this.downloadAudio(ctx);
      
      try {
        // Update processing message
        await ctx.telegram.editMessageText(
          ctx.chat.id, 
          processingMsg.message_id, 
          null, 
          '🎤 Обробляю голосове повідомлення...\n🔄 Перекладаю...'
        );

        // Check if user can make translation (token limits)
        const canTranslate = await databaseService.canUserMakeTranslation(user._id, 150);
        if (!canTranslate) {
          const limits = user.getCurrentLimits();
          await ctx.telegram.editMessageText(
            ctx.chat.id,
            processingMsg.message_id,
            null,
            `⚠️ **Ліміт вичерпано**\n\n${limits.type === 'premium' ? '👑' : '🆓'} Ви досягли ${limits.type === 'premium' ? 'преміум' : 'безкоштовного'} ліміту використання.\n\n💎 ${limits.type === 'free' ? 'Розглядайте можливість преміум підписки для x10 більших лімітів!' : 'Спробуйте пізніше.'}`
          );
          return;
        }

        let result;
        
        // Check if user is premium
        if (user.isPremium && user.hasPremiumFeature('autoLanguageDetection')) {
          // Premium users get automatic language detection with GPT enhancement
          await ctx.telegram.editMessageText(
            ctx.chat.id, 
            processingMsg.message_id, 
            null, 
            '👑 Обробляю голосове повідомлення...\n🧠 Автоматичне розпізнавання мови (GPT + Whisper)...'
          );
          
          result = await openaiService.completeTranslationAuto(
            audioPath,
            userSettings.primaryLanguage,
            userSettings.secondaryLanguage,
            true // isPremium = true
          );
        } else {
          // Free users need to select language manually (we'll use primary as default for now)
          await ctx.telegram.editMessageText(
            ctx.chat.id, 
            processingMsg.message_id, 
            null, 
            '🆓 Обробляю голосове повідомлення...\n🎤 Базове розпізнавання мови...'
          );
          
          result = await openaiService.completeTranslationManual(
            audioPath,
            userSettings.primaryLanguage,
            userSettings.secondaryLanguage
          );
        }

        // Update processing message
        await ctx.telegram.editMessageText(
          ctx.chat.id, 
          processingMsg.message_id, 
          null, 
          '🎤 Обробляю голосове повідомлення...\n💾 Зберігаю результат...'
        );

        // Update user stats and token usage
        await databaseService.incrementUserTranslations(user._id);
        await databaseService.addUserTokenUsage(user._id, result.tokensUsed || 150);

        // Format and send result
        await this.sendTranslationResult(ctx, result, user);
        
        // Delete processing message
        await ctx.telegram.deleteMessage(ctx.chat.id, processingMsg.message_id);

      } finally {
        // Clean up audio file
        await this.cleanupAudioFile(audioPath);
      }

    } catch (error) {
      logger.error('Error processing voice message:', error);
      await ctx.reply('❌ Виникла помилка при обробці голосового повідомлення. Спробуйте ще раз.');
    }
  }

  /**
   * Download audio file from Telegram
   */
  async downloadAudio(ctx) {
    try {
      const voice = ctx.message.voice;
      const fileId = voice.file_id;
      
      // Get file info from Telegram
      const fileInfo = await ctx.telegram.getFile(fileId);
      const fileUrl = `https://api.telegram.org/file/bot${config.telegram.token}/${fileInfo.file_path}`;
      
      // Generate unique filename
      const timestamp = Date.now();
      const fileName = `voice_${ctx.from.id}_${timestamp}.ogg`;
      const filePath = path.join(config.bot.tempAudioDir, fileName);
      
      // Ensure directory exists
      await fs.ensureDir(config.bot.tempAudioDir);
      
      // Download file
      const response = await axios({
        method: 'GET',
        url: fileUrl,
        responseType: 'stream'
      });
      
      const writer = fs.createWriteStream(filePath);
      response.data.pipe(writer);
      
      return new Promise((resolve, reject) => {
        writer.on('finish', () => {
          logger.info(`Audio file downloaded: ${filePath}`);
          resolve(filePath);
        });
        writer.on('error', reject);
      });

    } catch (error) {
      logger.error('Error downloading audio file:', error);
      throw error;
    }
  }

  /**
   * Send formatted translation result
   */
  async sendTranslationResult(ctx, result, user) {
    try {
      const detectedLang = languageService.getLanguageInfo(result.detectedLanguage);
      const targetLang = languageService.getLanguageInfo(result.targetLanguage);
      const primaryLang = languageService.getLanguageInfo(user.languages.primaryLanguage);
      const secondaryLang = languageService.getLanguageInfo(user.languages.secondaryLanguage);
      
      // Build main translation message
      let message = `🌍 **${targetLang.flag} ПЕРЕКЛАД:**
**${result.translated}**

🎤 *Розпізнано* (${detectedLang.flag} ${detectedLang.name}):
${result.original}`;

      // Add back-translation for Premium users only
      if (result.isPremium && result.backTranslation) {
        message += `\n\n🔄 *Зворотній переклад* (${detectedLang.flag} ${detectedLang.name}):
${result.backTranslation}`;
      }

      // Add language detection info based on user type
      let detectionInfo = '';
      if (result.isPremium && result.whisperDetection && result.gptDetection) {
        const whisperLang = languageService.getLanguageInfo(result.whisperDetection);
        const gptLang = languageService.getLanguageInfo(result.gptDetection);
        
        if (result.whisperDetection === result.gptDetected) {
          detectionInfo = `\n🔍 *Розпізнавання:* 👑 Whisper + GPT погодились: ${detectedLang.flag} ${detectedLang.name}`;
        } else {
          detectionInfo = `\n🔍 *Розпізнавання:* 👑 Whisper: ${whisperLang.flag} ${whisperLang.name}, GPT: ${gptLang.flag} ${gptLang.name} → ${detectedLang.flag} ${detectedLang.name}`;
        }
      } else if (!result.isPremium) {
        detectionInfo = `\n🔍 *Розпізнавання:* 🆓 Базове (тільки Whisper)`;
      }

      // Add user info and statistics
      message += `\n\n🤖 *Ваші мови:* ${primaryLang.flag} ${primaryLang.name} ⇄ ${secondaryLang.flag} ${secondaryLang.name}
📊 *Всього перекладів:* ${user.stats.totalTranslations + 1}${detectionInfo}`;

      // Add subscription info and features
      if (result.isPremium) {
        message += `\n\n👑 **ПРЕМІУМ ФУНКЦІЇ:**
✅ Автоматичне розпізнавання мови (GPT + Whisper)
✅ Зворотній переклад для перевірки
✅ x10 більше лімітів токенів`;
      } else {
        message += `\n\n🆓 **БЕЗКОШТОВНА ВЕРСІЯ**
💡 Преміум функції недоступні:
• Автоматичне розпізнавання мови
• Зворотній переклад
• Збільшені ліміти`;
      }

      // Build different keyboards for Premium and Free users
      let keyboard;
      if (result.isPremium) {
        // Premium users get language switching and limits
        keyboard = {
          inline_keyboard: [
            [
              {
                text: `🔄 ${primaryLang.flag} ⇄ ${secondaryLang.flag} Поміняти мови`,
                callback_data: 'switch_languages'
              }
            ],
            [
              {
                text: '📊 Мої ліміти',
                callback_data: 'show_limits'
              },
              {
                text: '⚙️ Налаштування',
                callback_data: 'settings'
              }
            ]
          ]
        };
      } else {
        // Free users get language switching, limits, and upgrade option
        keyboard = {
          inline_keyboard: [
            [
              {
                text: `🔄 ${primaryLang.flag} ⇄ ${secondaryLang.flag} Поміняти мови`,
                callback_data: 'switch_languages'
              }
            ],
            [
              {
                text: '📊 Мої ліміти',
                callback_data: 'show_limits'
              },
              {
                text: '💎 Преміум',
                callback_data: 'upgrade_premium'
              }
            ]
          ]
        };
      }

      await ctx.reply(message, {
        parse_mode: 'Markdown',
        reply_markup: keyboard
      });

      logger.info(`${result.isPremium ? 'Premium' : 'Free'} translation sent for user ${ctx.from.id}`);
    } catch (error) {
      logger.error('Error sending translation result:', error);
      throw error;
    }
  }

  /**
   * Handle audio messages (MP3, etc.)
   */
  async handleAudio(ctx) {
    try {
      const userId = ctx.from.id;
      logger.info(`Processing audio message from user ${userId}`);
      
      // For now, redirect to voice handler
      // In the future, you might want to handle different audio formats differently
      await ctx.reply('🎵 Будь ласка, надішліть голосове повідомлення (не аудіо файл) для кращої якості розпізнавання.');
    } catch (error) {
      logger.error('Error handling audio message:', error);
      await ctx.reply('❌ Виникла помилка при обробці аудіо повідомлення.');
    }
  }

  /**
   * Clean up temporary audio file
   */
  async cleanupAudioFile(filePath) {
    try {
      if (await fs.pathExists(filePath)) {
        await fs.remove(filePath);
        logger.info(`Cleaned up audio file: ${filePath}`);
      }
    } catch (error) {
      logger.error('Error cleaning up audio file:', error);
    }
  }

  /**
   * Handle document messages (in case user sends audio as document)
   */
  async handleDocument(ctx) {
    try {
      const document = ctx.message.document;
      
      // Check if it's an audio file
      if (document.mime_type && document.mime_type.startsWith('audio/')) {
        await ctx.reply('🎵 Я отримав аудіо файл, але для кращої якості розпізнавання рекомендую надсилати голосові повідомлення через мікрофон в Telegram.');
        
        // You could implement document audio processing here if needed
        // For now, we'll just suggest using voice messages
      } else {
        await ctx.reply('📄 Я обробляю лише голосові повідомлення. Будь ласка, надішліть голосове повідомлення для перекладу.');
      }
    } catch (error) {
      logger.error('Error handling document:', error);
      await ctx.reply('❌ Виникла помилка при обробці документа.');
    }
  }
}

module.exports = new AudioHandler(); 