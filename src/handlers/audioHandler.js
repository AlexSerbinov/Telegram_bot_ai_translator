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
      logger.info(`Processing voice message from user ${userId}`);

      // Get or create active chat with current language settings
      const languagePair = {
        from: userSettings.primaryLanguage,
        to: userSettings.secondaryLanguage
      };
      
      const activeChat = await databaseService.getOrCreateUserActiveChat(user._id, languagePair);
      
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
          await ctx.telegram.editMessageText(
            ctx.chat.id,
            processingMsg.message_id,
            null,
            '⚠️ **Ліміт вичерпано**\n\nВи досягли денного або місячного ліміту використання.\n\n💎 Розглядайте можливість преміум підписки для необмежених перекладів!'
          );
          return;
        }

        // Process translation with automatic language detection
        const result = await openaiService.completeTranslationAuto(
          audioPath,
          userSettings.primaryLanguage,
          userSettings.secondaryLanguage
        );

        // Update processing message
        await ctx.telegram.editMessageText(
          ctx.chat.id, 
          processingMsg.message_id, 
          null, 
          '🎤 Обробляю голосове повідомлення...\n💾 Зберігаю результат...'
        );

        // Save translation to database
        const translationData = {
          original: {
            text: result.original,
            language: result.detectedLanguage
          },
          translated: {
            text: result.translated,
            language: result.targetLanguage
          },
          backTranslation: result.backTranslation,
          tokensUsed: result.tokensUsed || 150,
          audioFile: {
            telegramFileId: ctx.message.voice.file_id,
            duration: ctx.message.voice.duration,
            size: ctx.message.voice.file_size
          }
        };

        await databaseService.addTranslationToChat(activeChat._id, translationData);
        
        // Add token usage to user
        await databaseService.addUserTokenUsage(user._id, translationData.tokensUsed);

        // Format and send result
        await this.sendTranslationResult(ctx, result, userSettings, activeChat);
        
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
  async sendTranslationResult(ctx, result, userSettings, activeChat) {
    try {
      const detectedLang = languageService.getLanguageInfo(result.detectedLanguage);
      const targetLang = languageService.getLanguageInfo(result.targetLanguage);
      const primaryLang = languageService.getLanguageInfo(userSettings.primaryLanguage);
      const secondaryLang = languageService.getLanguageInfo(userSettings.secondaryLanguage);
      
      // Build language detection info if available
      let detectionInfo = '';
      if (result.whisperDetection && result.gptDetection) {
        const whisperLang = languageService.getLanguageInfo(result.whisperDetection);
        const gptLang = languageService.getLanguageInfo(result.gptDetection);
        
        if (result.whisperDetection === result.gptDetection) {
          detectionInfo = `\n🔍 *Розпізнавання:* Whisper та GPT погодились на ${detectedLang.flag} ${detectedLang.name}`;
        } else {
          detectionInfo = `\n🔍 *Розпізнавання:* Whisper: ${whisperLang.flag} ${whisperLang.name}, GPT: ${gptLang.flag} ${gptLang.name} → Обрано: ${detectedLang.flag} ${detectedLang.name}`;
        }
      }
      
      const message = `🌍 **${targetLang.flag} ПЕРЕКЛАД:**
**${result.translated}**

🎤 *Розпізнано* (${detectedLang.flag} ${detectedLang.name}):
${result.original}

🔄 *Зворотній переклад* (${detectedLang.flag} ${detectedLang.name}):
${result.backTranslation}

🤖 *Ваші мови:* ${primaryLang.flag} ${primaryLang.name} ⇄ ${secondaryLang.flag} ${secondaryLang.name}
💬 *Чат:* ${activeChat.title} | 📊 ${activeChat.stats.totalTranslations} перекладів${detectionInfo}

💡 Покращена система автоматично розпізнала мову та перевела на відповідну.`;

      const keyboard = {
        inline_keyboard: [
          [
            {
              text: `🔄 ${primaryLang.flag} ⇄ ${secondaryLang.flag} Switch`,
              callback_data: 'switch_and_speak'
            }
          ],
          [
            {
              text: '💬 Новий чат',
              callback_data: 'new_chat'
            },
            {
              text: '📚 Історія чатів',
              callback_data: 'chat_history'
            }
          ],
          [
            {
              text: '📊 Мої ліміти',
              callback_data: 'show_limits'
            }
          ]
        ]
      };

      await ctx.reply(message, {
        parse_mode: 'Markdown',
        reply_markup: keyboard
      });

      logger.info(`Translation sent for user ${ctx.from.id} in chat ${activeChat._id}`);
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