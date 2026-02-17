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

        // Check if user is premium
        if (user.isPremium && user.hasPremiumFeature('autoLanguageDetection')) {
          // Premium users get automatic language detection with GPT enhancement
          await ctx.telegram.editMessageText(
            ctx.chat.id, 
            processingMsg.message_id, 
            null, 
            '👑 Обробляю голосове повідомлення...\n🧠 Автоматичне розпізнавання мови (GPT + Whisper)...'
          );
          
          const result = await openaiService.completeTranslationAuto(
            audioPath,
            userSettings.primaryLanguage,
            userSettings.secondaryLanguage,
            true // isPremium = true
          );

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
        } else {
          // Free users need to select language before speaking
          // Check if user has already selected language
          if (user.isWaitingForVoice() && user.voiceState.selectedInputLanguage) {
            // User has selected language, process directly
            const inputLang = user.voiceState.selectedInputLanguage;
            const outputLang = inputLang === userSettings.primaryLanguage ? 
              userSettings.secondaryLanguage : userSettings.primaryLanguage;

            await ctx.telegram.editMessageText(
              ctx.chat.id, 
              processingMsg.message_id, 
              null, 
              `🆓 Обробляю голосове повідомлення...\n🔄 Перекладаю з ${languageService.getLanguageInfo(inputLang).name}...`
            );

            try {
              // Process translation with known language (no language detection for free users)
              const result = await openaiService.completeTranslationManual(
                audioPath,
                inputLang,
                outputLang
              );

              // Update processing message
              await ctx.telegram.editMessageText(
                ctx.chat.id, 
                processingMsg.message_id, 
                null, 
                '🆓 Обробляю голосове повідомлення...\n💾 Зберігаю результат...'
              );

              // Update user stats and token usage
              await databaseService.incrementUserTranslations(user._id);
              await databaseService.addUserTokenUsage(user._id, result.tokensUsed || 150);

              // Clear voice state
              user.clearVoiceState();
              await user.save();

              // Format and send result
              await this.sendTranslationResult(ctx, result, user);
              
              // Delete processing message
              await ctx.telegram.deleteMessage(ctx.chat.id, processingMsg.message_id);

            } catch (error) {
              logger.error('Error processing free user translation:', error);
              await ctx.telegram.editMessageText(
                ctx.chat.id,
                processingMsg.message_id,
                null,
                '❌ Виникла помилка при обробці. Спробуйте ще раз.'
              );
              user.clearVoiceState();
              await user.save();
            }
          } else {
            // Check if user has a last selected language
            if (user.voiceState.lastSelectedLanguage) {
              // Use last selected language automatically
              const inputLang = user.voiceState.lastSelectedLanguage;
              const outputLang = inputLang === userSettings.primaryLanguage ? 
                userSettings.secondaryLanguage : userSettings.primaryLanguage;

              await ctx.telegram.editMessageText(
                ctx.chat.id, 
                processingMsg.message_id, 
                null, 
                `🆓 Обробляю голосове повідомлення...\n🔄 Перекладаю з ${languageService.getLanguageInfo(inputLang).name}...`
              );

              try {
                // Process translation with last selected language
                const result = await openaiService.completeTranslationManual(
                  audioPath,
                  inputLang,
                  outputLang
                );

                // Update processing message
                await ctx.telegram.editMessageText(
                  ctx.chat.id, 
                  processingMsg.message_id, 
                  null, 
                  '🆓 Обробляю голосове повідомлення...\n💾 Зберігаю результат...'
                );

                // Update user stats and token usage
                await databaseService.incrementUserTranslations(user._id);
                await databaseService.addUserTokenUsage(user._id, result.tokensUsed || 150);

                // Format and send result
                await this.sendTranslationResult(ctx, result, user);
                
                // Delete processing message
                await ctx.telegram.deleteMessage(ctx.chat.id, processingMsg.message_id);

              } catch (error) {
                logger.error('Error processing free user translation with remembered language:', error);
                await ctx.telegram.editMessageText(
                  ctx.chat.id,
                  processingMsg.message_id,
                  null,
                  '❌ Виникла помилка при обробці. Спробуйте ще раз.'
                );
              }
            } else {
              // User needs to select language first - show selection directly
              await ctx.telegram.editMessageText(
                ctx.chat.id,
                processingMsg.message_id,
                null,
                `🆓 **Спочатку оберіть мову для диктування**

❗ Для безкоштовної версії потрібно спочатку вибрати мову, а потім диктувати.

🎤 Якою мовою ви будете говорити?`,
                {
                  parse_mode: 'Markdown',
                  reply_markup: await this.getLanguageSelectionKeyboard(user)
                }
              );

              // Clean up the audio file since we can't process it now
              await this.cleanupAudioFile(audioPath);
            }
          }
        }

      } finally {
        // Clean up audio file only for premium users (free users need it for later processing)
        if (user.isPremium && user.hasPremiumFeature('autoLanguageDetection')) {
          await this.cleanupAudioFile(audioPath);
        }
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

      // Simple format: just translation and original
      const message = `${targetLang.flag} **${result.translated}**

🗣️ Оригінал (${detectedLang.flag}): ${result.original}`;

      // Reply keyboard with two language buttons
      const primaryLang = config.languages[user.languages.primaryLanguage];
      const secondaryLang = config.languages[user.languages.secondaryLanguage];

      const keyboard = {
        keyboard: [
          [
            { text: `🎤 ${primaryLang.flag} ${primaryLang.nameUk}` },
            { text: `🎤 ${secondaryLang.flag} ${secondaryLang.nameUk}` }
          ]
        ],
        resize_keyboard: true
      };

      await ctx.reply(message, {
        parse_mode: 'Markdown',
        reply_markup: keyboard
      });

      logger.info(`Translation sent for user ${ctx.from.id}`);
    } catch (error) {
      logger.error('Error sending translation result:', error);
      throw error;
    }
  }

  /**
   * Handle reply keyboard language button press
   * Returns true if the text was a language button, false otherwise
   */
  async handleLanguageButton(ctx) {
    const text = ctx.message.text;
    if (!text || !text.startsWith('🎤')) return false;

    const userId = ctx.from.id;
    const user = await databaseService.getUserByTelegramId(userId);
    if (!user) return false;

    // Match button text to language code
    let matchedLangCode = null;
    for (const [code, lang] of Object.entries(config.languages)) {
      if (text === `🎤 ${lang.flag} ${lang.nameUk}`) {
        matchedLangCode = code;
        break;
      }
    }

    if (!matchedLangCode) return false;

    // Set voice language
    user.setVoiceInputLanguage(matchedLangCode);
    user.voiceState.lastSelectedLanguage = matchedLangCode;
    await user.save();

    const langInfo = config.languages[matchedLangCode];
    const targetCode = matchedLangCode === user.languages.primaryLanguage
      ? user.languages.secondaryLanguage
      : user.languages.primaryLanguage;
    const targetInfo = config.languages[targetCode];

    await ctx.reply(
      `✅ Диктуйте ${langInfo.flag} ${langInfo.nameUk} → перекладу на ${targetInfo.flag} ${targetInfo.nameUk}\n\n🎤 Надішліть голосове повідомлення`,
      { parse_mode: 'Markdown' }
    );

    logger.info(`User ${userId} selected dictation language: ${matchedLangCode} via reply keyboard`);
    return true;
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
   * Get language selection keyboard for free users
   */
  async getLanguageSelectionKeyboard(user) {
    const userSettings = user.languages;
    const primaryLang = languageService.getLanguageInfo(userSettings.primaryLanguage);
    const secondaryLang = languageService.getLanguageInfo(userSettings.secondaryLanguage);
    
    // Check if user has a last selected language to highlight it
    const lastSelected = user.voiceState.lastSelectedLanguage;
    
    // Build buttons with last selected indicated
    const primaryText = lastSelected === userSettings.primaryLanguage ? 
      `✅ ${primaryLang.flag} Диктувати ${primaryLang.name} (останній раз)` :
      `${primaryLang.flag} Диктувати ${primaryLang.name}`;
      
    const secondaryText = lastSelected === userSettings.secondaryLanguage ? 
      `✅ ${secondaryLang.flag} Диктувати ${secondaryLang.name} (останній раз)` :
      `${secondaryLang.flag} Диктувати ${secondaryLang.name}`;

    return {
      inline_keyboard: [
        [
          {
            text: primaryText,
            callback_data: `set_voice_lang_${userSettings.primaryLanguage}`
          }
        ],
        [
          {
            text: secondaryText,
            callback_data: `set_voice_lang_${userSettings.secondaryLanguage}`
          }
        ],
        [
          {
            text: '⚙️ Налаштування мов',
            callback_data: 'open_settings'
          }
        ]
      ]
    };
  }

  /**
   * Show language selection for free users (DEPRECATED - use getLanguageSelectionKeyboard)
   */
  async showLanguageSelectionForFreeUser(ctx, user) {
    try {
      const userSettings = user.languages;
      const primaryLang = languageService.getLanguageInfo(userSettings.primaryLanguage);
      const secondaryLang = languageService.getLanguageInfo(userSettings.secondaryLanguage);

      const message = `🎯 **Оберіть мову для диктування**

🎤 Якою мовою ви будете говорити?

Після вибору мови надішліть голосове повідомлення.`;

      await ctx.reply(message, {
        parse_mode: 'Markdown',
        reply_markup: await this.getLanguageSelectionKeyboard(user)
      });
    } catch (error) {
      logger.error('Error showing language selection for free user:', error);
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