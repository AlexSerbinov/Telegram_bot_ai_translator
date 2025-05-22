const languageService = require('../services/languageService');
const openaiService = require('../services/openaiService');
const databaseService = require('../services/databaseService');
const logger = require('../utils/logger');
const path = require('path');
const fs = require('fs-extra');
const { config } = require('../config/config');

class CallbackHandlers {

  /**
   * Handle opening settings
   */
  async handleOpenSettings(ctx) {
    try {
      const userId = ctx.from.id;
      logger.info(`User ${userId} opened settings via callback`);
      
      const currentSettings = await languageService.formatCurrentSettings(userId);
      const keyboard = await languageService.generateSettingsKeyboard(userId);
      
      const message = `⚙️ **Налаштування перекладача**

${currentSettings}

Виберіть, що хочете змінити:`;

      await ctx.editMessageText(message, {
        parse_mode: 'Markdown',
        reply_markup: keyboard
      });
      
      await ctx.answerCbQuery();
    } catch (error) {
      logger.error('Error in handleOpenSettings:', error);
      await ctx.answerCbQuery('❌ Виникла помилка');
    }
  }

  /**
   * Handle showing help via callback
   */
  async handleShowHelp(ctx) {
    try {
      const helpMessage = `📖 **Довідка AI Translator Bot**

🎤 **Основні функції:**
• Speech-to-Text: Розпізнавання мови з аудіо
• Переклад тексту між мовами
• Верифікація якості через зворотній переклад
• Генерація голосового перекладу

🔧 **Команди:**
/start - Запустити бота
/menu - Головне меню
/settings - Налаштування мов
/limits - Переглянути ліміти використання
/stats - Детальна статистика
/help - Показати цю довідку

🌍 **Підтримувані мови:**
🇺🇦 Українська • 🇺🇸 English • 🇬🇪 ქართული
🇮🇩 Bahasa Indonesia • 🇷🇺 Русский

📝 **Як користуватися:**
1. Налаштуйте мови в /settings
2. Надішліть голосове повідомлення
3. Отримайте переклад з верифікацією
4. Використовуйте кнопку Switch для зміни мов`;

      await ctx.editMessageText(helpMessage, {
        parse_mode: 'Markdown',
        reply_markup: {
          inline_keyboard: [
            [
              {
                text: '⚙️ Налаштування',
                callback_data: 'open_settings'
              }
            ]
          ]
        }
      });
      
      await ctx.answerCbQuery();
    } catch (error) {
      logger.error('Error in handleShowHelp:', error);
      await ctx.answerCbQuery('❌ Виникла помилка');
    }
  }

  /**
   * Handle changing primary language
   */
  async handleChangePrimaryLanguage(ctx) {
    try {
      const keyboard = languageService.generateLanguageKeyboard('primary');
      
      await ctx.editMessageText('1️⃣ Оберіть першу мову:', {
        reply_markup: keyboard
      });
      
      await ctx.answerCbQuery();
    } catch (error) {
      logger.error('Error in handleChangePrimaryLanguage:', error);
      await ctx.answerCbQuery('❌ Виникла помилка');
    }
  }

  /**
   * Handle changing secondary language
   */
  async handleChangeSecondaryLanguage(ctx) {
    try {
      const keyboard = languageService.generateLanguageKeyboard('secondary');
      
      await ctx.editMessageText('2️⃣ Оберіть другу мову:', {
        reply_markup: keyboard
      });
      
      await ctx.answerCbQuery();
    } catch (error) {
      logger.error('Error in handleChangeSecondaryLanguage:', error);
      await ctx.answerCbQuery('❌ Виникла помилка');
    }
  }

  /**
   * Handle language selection
   */
  async handleLanguageSelection(ctx, type, languageCode) {
    try {
      const userId = ctx.from.id;
      const languageInfo = languageService.getLanguageInfo(languageCode);
      
      if (!languageInfo) {
        await ctx.answerCbQuery('❌ Невідома мова');
        return;
      }

      const currentSettings = await languageService.getUserLanguages(userId);
      
      if (type === 'primary') {
        await languageService.setUserLanguages(userId, languageCode, currentSettings.secondaryLanguage);
        await ctx.answerCbQuery(`✅ Першу мову змінено на ${languageInfo.name}`);
      } else if (type === 'secondary') {
        await languageService.setUserLanguages(userId, currentSettings.primaryLanguage, languageCode);
        await ctx.answerCbQuery(`✅ Другу мову змінено на ${languageInfo.name}`);
      }

      // Return to settings
      setTimeout(async () => {
        try {
          const newSettings = await languageService.formatCurrentSettings(userId);
          const keyboard = await languageService.generateSettingsKeyboard(userId);
          
          const message = `⚙️ **Налаштування перекладача**

${newSettings}

Виберіть, що хочете змінити:`;

          await ctx.editMessageText(message, {
            parse_mode: 'Markdown',
            reply_markup: keyboard
          });
        } catch (error) {
          logger.error('Error updating settings after language change:', error);
        }
      }, 1000);

    } catch (error) {
      logger.error('Error in handleLanguageSelection:', error);
      await ctx.answerCbQuery('❌ Виникла помилка');
    }
  }

  /**
   * Handle switching languages
   */
  async handleSwitchLanguages(ctx) {
    try {
      const userId = ctx.from.id;
      const newSettings = await languageService.switchUserLanguages(userId);
      
      const settingsText = await languageService.formatCurrentSettings(userId);
      const keyboard = await languageService.generateSettingsKeyboard(userId);
      
      const message = `⚙️ **Налаштування перекладача**

${settingsText}

Виберіть, що хочете змінити:`;

      await ctx.editMessageText(message, {
        parse_mode: 'Markdown',
        reply_markup: keyboard
      });
      
      await ctx.answerCbQuery('🔄 Мови поміняно місцями!');
    } catch (error) {
      logger.error('Error in handleSwitchLanguages:', error);
      await ctx.answerCbQuery('❌ Виникла помилка');
    }
  }

  /**
   * Handle settings done
   */
  async handleSettingsDone(ctx) {
    try {
      const userId = ctx.from.id;
      const settings = await languageService.formatCurrentSettings(userId);
      
      const message = `✅ **Налаштування збережено!**

${settings}

Тепер надішліть голосове повідомлення для перекладу 🎤`;

      await ctx.editMessageText(message, {
        parse_mode: 'Markdown'
      });
      
      await ctx.answerCbQuery('✅ Налаштування збережено!');
    } catch (error) {
      logger.error('Error in handleSettingsDone:', error);
      await ctx.answerCbQuery('❌ Виникла помилка');
    }
  }

  /**
   * Handle switch functionality - swap source and target languages
   */
  async handleSwitchAndSpeak(ctx) {
    try {
      const userId = ctx.from.id;
      
      // Switch languages
      const newSettings = await languageService.switchUserLanguages(userId);
      
      const newPrimaryLang = languageService.getLanguageInfo(newSettings.primaryLanguage);
      const newSecondaryLang = languageService.getLanguageInfo(newSettings.secondaryLanguage);
      
      // Send confirmation message about language switch
      const switchMessage = `🔄 **Мови переключено!**

🤖 **Ваші мови тепер:**
1️⃣ ${newPrimaryLang.flag} ${newPrimaryLang.name}
2️⃣ ${newSecondaryLang.flag} ${newSecondaryLang.name}

💡 Система автоматично розпізнає мову та перекладе на відповідну!
Надішліть голосове повідомлення 🎤`;

      await ctx.reply(switchMessage, {
        parse_mode: 'Markdown',
        reply_markup: {
          inline_keyboard: [
            [
              {
                text: '⚙️ Налаштування мов',
                callback_data: 'open_settings'
              }
            ],
            [
              {
                text: '💬 Новий чат',
                callback_data: 'new_chat'
              },
              {
                text: '📊 Мої ліміти',
                callback_data: 'show_limits'
              }
            ]
          ]
        }
      });
      
      await ctx.answerCbQuery(`🔄 Мови переключено!`);
      
    } catch (error) {
      logger.error('Error in handleSwitchAndSpeak:', error);
      await ctx.answerCbQuery('❌ Виникла помилка при переключенні мов');
    }
  }

  /**
   * Handle showing user limits
   */
  async handleShowLimits(ctx) {
    try {
      const userId = ctx.from.id;
      logger.info(`User ${userId} viewing limits`);

      const user = await databaseService.getUserByTelegramId(userId);
      if (!user) {
        await ctx.answerCbQuery('❌ Помилка: користувач не знайден');
        return;
      }

      const userStats = await databaseService.getUserStats(user._id);
      const { tokenLimits } = require('../config/config').config;

      // Calculate remaining limits
      const dailyRemaining = Math.max(0, tokenLimits.freeTierDaily - userStats.tokenUsage.dailyUsed);
      const monthlyRemaining = Math.max(0, tokenLimits.freeTierMonthly - userStats.tokenUsage.monthlyUsed);

      // Calculate percentages
      const dailyPercent = Math.round((userStats.tokenUsage.dailyUsed / tokenLimits.freeTierDaily) * 100);
      const monthlyPercent = Math.round((userStats.tokenUsage.monthlyUsed / tokenLimits.freeTierMonthly) * 100);

      // Progress bars
      const dailyBar = this.generateProgressBar(dailyPercent, 20);
      const monthlyBar = this.generateProgressBar(monthlyPercent, 20);

      const limitsMessage = `📊 **Ваші ліміти використання**

👤 **Підписка:** ${userStats.subscription.type === 'premium' ? '💎 Premium' : '🆓 Безкоштовна'}

📈 **Денний ліміт:**
${dailyBar} ${dailyPercent}%
• Використано: ${userStats.tokenUsage.dailyUsed}
• Залишилось: ${dailyRemaining}
• Всього: ${tokenLimits.freeTierDaily}

📊 **Місячний ліміт:**
${monthlyBar} ${monthlyPercent}%
• Використано: ${userStats.tokenUsage.monthlyUsed}
• Залишилось: ${monthlyRemaining}
• Всього: ${tokenLimits.freeTierMonthly}

💡 **Статистика:**
• Всього перекладів: ${userStats.stats.totalTranslations}
• Всього токенів: ${userStats.tokenUsage.totalUsed}

${userStats.subscription.type === 'free' ? '\n💎 Преміум підписка дає необмежені переклади!' : ''}`;

      await ctx.editMessageText(limitsMessage, {
        parse_mode: 'Markdown',
        reply_markup: {
          inline_keyboard: [
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
                text: '⚙️ Налаштування',
                callback_data: 'open_settings'
              }
            ]
          ]
        }
      });

      await ctx.answerCbQuery();
    } catch (error) {
      logger.error('Error in handleShowLimits:', error);
      await ctx.answerCbQuery('❌ Виникла помилка при завантаженні лімітів');
    }
  }

  /**
   * Generate progress bar for limits display
   */
  generateProgressBar(percentage, length = 20) {
    const filled = Math.round((percentage / 100) * length);
    const empty = length - filled;
    
    let bar = '';
    for (let i = 0; i < filled; i++) {
      bar += '█';
    }
    for (let i = 0; i < empty; i++) {
      bar += '░';
    }
    
    return bar;
  }

  /**
   * Handle new chat creation
   */
  async handleNewChat(ctx) {
    try {
      const userId = ctx.from.id;
      logger.info(`User ${userId} creating new chat`);

      // Get user and current language settings
      const user = await databaseService.getUserByTelegramId(userId);
      if (!user) {
        await ctx.answerCbQuery('❌ Помилка: користувач не знайден');
        return;
      }

      const languagePair = {
        from: user.languages.primaryLanguage,
        to: user.languages.secondaryLanguage
      };

      // Create new chat
      const newChat = await databaseService.createChat(user._id, languagePair);

      const primaryLang = languageService.getLanguageInfo(languagePair.from);
      const secondaryLang = languageService.getLanguageInfo(languagePair.to);

      await ctx.editMessageText(`💬 **Новий чат створено!**

📝 **ID чату:** ${newChat._id.toString().slice(-6)}
🤖 **Ваші мови:**
1️⃣ ${primaryLang.flag} ${primaryLang.name}
2️⃣ ${secondaryLang.flag} ${secondaryLang.name}

💡 Система автоматично розпізнає мову та перекладе на відповідну!
Надішліть голосове повідомлення 🎤`, {
        parse_mode: 'Markdown',
        reply_markup: {
          inline_keyboard: [
            [
              {
                text: '⚙️ Змінити мови',
                callback_data: 'open_settings'
              }
            ],
            [
              {
                text: '📚 Історія чатів',
                callback_data: 'chat_history'
              }
            ]
          ]
        }
      });

      await ctx.answerCbQuery('✅ Новий чат створено!');
    } catch (error) {
      logger.error('Error in handleNewChat:', error);
      await ctx.answerCbQuery('❌ Виникла помилка при створенні чату');
    }
  }

  /**
   * Handle chat history display
   */
  async handleChatHistory(ctx) {
    try {
      const userId = ctx.from.id;
      logger.info(`User ${userId} viewing chat history`);

      const user = await databaseService.getUserByTelegramId(userId);
      if (!user) {
        await ctx.answerCbQuery('❌ Помилка: користувач не знайден');
        return;
      }

      const chats = await databaseService.getUserChats(user._id, 10);

      if (chats.length === 0) {
        await ctx.editMessageText('📚 **Історія чатів**\n\nУ вас поки немає жодного чату.\nСтворіть новий чат для початку роботи!', {
          parse_mode: 'Markdown',
          reply_markup: {
            inline_keyboard: [
              [
                {
                  text: '💬 Створити новий чат',
                  callback_data: 'new_chat'
                }
              ]
            ]
          }
        });
        await ctx.answerCbQuery();
        return;
      }

      let message = '📚 **Історія чатів**\n\n';
      const keyboard = [];

      chats.forEach((chat, index) => {
        const fromLang = languageService.getLanguageInfo(chat.languagePair.from);
        const toLang = languageService.getLanguageInfo(chat.languagePair.to);
        const lastActivity = new Date(chat.stats.lastActivity).toLocaleDateString('uk-UA');
        
        message += `${index + 1}. **${chat.title}**\n`;
        message += `   ${fromLang.flag} → ${toLang.flag} | 💬 ${chat.stats.totalTranslations} | 📅 ${lastActivity}\n\n`;

        keyboard.push([
          {
            text: `📖 ${chat.title.substring(0, 30)}${chat.title.length > 30 ? '...' : ''}`,
            callback_data: `view_chat_${chat._id}`
          }
        ]);
      });

      keyboard.push([
        {
          text: '💬 Новий чат',
          callback_data: 'new_chat'
        }
      ]);

      await ctx.editMessageText(message, {
        parse_mode: 'Markdown',
        reply_markup: {
          inline_keyboard: keyboard
        }
      });

      await ctx.answerCbQuery();
    } catch (error) {
      logger.error('Error in handleChatHistory:', error);
      await ctx.answerCbQuery('❌ Виникла помилка при завантаженні історії');
    }
  }

  /**
   * Handle viewing specific chat
   */
  async handleViewChat(ctx, chatId) {
    try {
      const userId = ctx.from.id;
      logger.info(`User ${userId} viewing chat ${chatId}`);

      const chat = await databaseService.getChatWithTranslations(chatId, 5);
      if (!chat) {
        await ctx.answerCbQuery('❌ Чат не знайдено');
        return;
      }

      // Set as active chat
      const user = await databaseService.getUserByTelegramId(userId);
      await databaseService.setUserActiveChat(user._id, chatId);

      const fromLang = languageService.getLanguageInfo(chat.languagePair.from);
      const toLang = languageService.getLanguageInfo(chat.languagePair.to);

      let message = `💬 **${chat.title}**\n\n`;
      message += `🎤 ${fromLang.flag} ${fromLang.name} → 🌍 ${toLang.flag} ${toLang.name}\n`;
      message += `📊 **Статистика:** ${chat.stats.totalTranslations} перекладів\n`;
      message += `📅 **Остання активність:** ${new Date(chat.stats.lastActivity).toLocaleDateString('uk-UA')}\n\n`;

      if (chat.translations.length > 0) {
        message += '**Останні переклади:**\n\n';
        chat.translations.slice(-3).forEach((translation, index) => {
          message += `${index + 1}. *${translation.original.text.substring(0, 50)}${translation.original.text.length > 50 ? '...' : ''}*\n`;
          message += `   ➡️ ${translation.translated.text.substring(0, 50)}${translation.translated.text.length > 50 ? '...' : ''}\n\n`;
        });
      }

      message += '**Чат активний!** Надішліть голосове повідомлення для продовження 🎤';

      await ctx.editMessageText(message, {
        parse_mode: 'Markdown',
        reply_markup: {
          inline_keyboard: [
            [
              {
                text: '💬 Новий чат',
                callback_data: 'new_chat'
              },
              {
                text: '📚 Назад до історії',
                callback_data: 'chat_history'
              }
            ],
            [
              {
                text: '🗄️ Архівувати чат',
                callback_data: `archive_chat_${chatId}`
              }
            ]
          ]
        }
      });

      await ctx.answerCbQuery('✅ Чат активовано!');
    } catch (error) {
      logger.error('Error in handleViewChat:', error);
      await ctx.answerCbQuery('❌ Виникла помилка при завантаженні чату');
    }
  }

  /**
   * Handle chat archiving
   */
  async handleArchiveChat(ctx, chatId) {
    try {
      const userId = ctx.from.id;
      logger.info(`User ${userId} archiving chat ${chatId}`);

      await databaseService.archiveChat(chatId);

      await ctx.editMessageText('🗄️ **Чат архівовано**\n\nЧат переміщено в архів. Ви можете створити новий чат для продовження роботи.', {
        parse_mode: 'Markdown',
        reply_markup: {
          inline_keyboard: [
            [
              {
                text: '💬 Новий чат',
                callback_data: 'new_chat'
              },
              {
                text: '📚 Історія чатів',
                callback_data: 'chat_history'
              }
            ]
          ]
        }
      });

      await ctx.answerCbQuery('🗄️ Чат архівовано');
    } catch (error) {
      logger.error('Error in handleArchiveChat:', error);
      await ctx.answerCbQuery('❌ Виникла помилка при архівуванні');
    }
  }

  /**
   * Main callback query router
   */
  async handleCallback(ctx) {
    const data = ctx.callbackQuery.data;
    
    logger.info(`Callback received: ${data} from user ${ctx.from.id}`);

    try {
      if (data === 'open_settings') {
        await this.handleOpenSettings(ctx);
      } else if (data === 'show_help') {
        await this.handleShowHelp(ctx);
      } else if (data === 'new_chat') {
        await this.handleNewChat(ctx);
      } else if (data === 'chat_history') {
        await this.handleChatHistory(ctx);
      } else if (data === 'show_limits') {
        await this.handleShowLimits(ctx);
      } else if (data === 'change_primary_language') {
        await this.handleChangePrimaryLanguage(ctx);
      } else if (data === 'change_secondary_language') {
        await this.handleChangeSecondaryLanguage(ctx);
      } else if (data === 'switch_languages') {
        await this.handleSwitchLanguages(ctx);
      } else if (data === 'settings_done') {
        await this.handleSettingsDone(ctx);
      } else if (data === 'switch_and_speak') {
        await this.handleSwitchAndSpeak(ctx);
      } else if (data.startsWith('lang_')) {
        const [, type, languageCode] = data.split('_');
        await this.handleLanguageSelection(ctx, type, languageCode);
      } else if (data.startsWith('view_chat_')) {
        const chatId = data.replace('view_chat_', '');
        await this.handleViewChat(ctx, chatId);
      } else if (data.startsWith('archive_chat_')) {
        const chatId = data.replace('archive_chat_', '');
        await this.handleArchiveChat(ctx, chatId);
      } else {
        await ctx.answerCbQuery('❌ Невідома команда');
      }
    } catch (error) {
      logger.error('Error in callback handler:', error);
      await ctx.answerCbQuery('❌ Виникла помилка');
    }
  }
}

module.exports = new CallbackHandlers(); 