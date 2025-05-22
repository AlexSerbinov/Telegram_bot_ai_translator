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
   * Handle settings done (close settings)
   */
  async handleSettingsDone(ctx) {
    try {
      const userId = ctx.from.id;
      const settingsText = await languageService.formatCurrentSettings(userId);
      
      // Get user info to determine subscription type
      const user = await databaseService.getUserByTelegramId(userId);
      
      let message, keyboard;
      
      if (user && user.subscriptionType === 'premium') {
        // Premium user - show automatic mode
        message = `✅ **Налаштування збережено!**

${settingsText}

👑 **Premium режим:** Система автоматично розпізнає мову та перекладе

Тепер ви можете надсилати голосові повідомлення для автоматичного перекладу 🎤`;

        keyboard = {
          inline_keyboard: [
            [
              {
                text: '📊 Мої ліміти',
                callback_data: 'show_limits'
              },
              {
                text: '📖 Довідка',
                callback_data: 'show_help'
              }
            ]
          ]
        };
      } else {
        // Free user - show language selection buttons
        const primaryLang = config.languages[user.languages.primaryLanguage];
        const secondaryLang = config.languages[user.languages.secondaryLanguage];
        
        message = `✅ **Налаштування збережено!**

${settingsText}

🆓 **Безкоштовний режим:** Спочатку оберіть мову диктування, потім записуйте голосове повідомлення

Оберіть мову диктування:`;

        keyboard = {
          inline_keyboard: [
            [
                             {
                 text: `🎤 Диктувати ${primaryLang.flag}`,
                 callback_data: `set_voice_lang_${user.languages.primaryLanguage}`
               },
               {
                 text: `🎤 Диктувати ${secondaryLang.flag}`,
                 callback_data: `set_voice_lang_${user.languages.secondaryLanguage}`
               }
            ],
            [
              {
                text: '📊 Мої ліміти',
                callback_data: 'show_limits'
              },
              {
                text: '📖 Довідка',
                callback_data: 'show_help'
              }
            ]
          ]
        };
      }

      await ctx.editMessageText(message, {
        parse_mode: 'Markdown',
        reply_markup: keyboard
      });
      
      await ctx.answerCbQuery('✅ Налаштування збережено!');
    } catch (error) {
      logger.error('Error in handleSettingsDone:', error);
      await ctx.answerCbQuery('❌ Виникла помилка');
    }
  }

  /**
   * Handle switch and speak functionality
   */
  async handleSwitchAndSpeak(ctx) {
    try {
      const userId = ctx.from.id;
      logger.info(`User ${userId} requested switch and speak`);
      
      // Switch languages
      const newSettings = await languageService.switchUserLanguages(userId);
      
      const primaryLang = languageService.getLanguageInfo(newSettings.primaryLanguage);
      const secondaryLang = languageService.getLanguageInfo(newSettings.secondaryLanguage);
      
      const message = `🔄 **Мови переключено!**

🤖 **Тепер активні мови:**
1️⃣ ${primaryLang.flag} ${primaryLang.name}
2️⃣ ${secondaryLang.flag} ${secondaryLang.name}

💡 Система автоматично розпізнає якою мовою ви говорите та перекладе на відповідну!
Надішліть голосове повідомлення 🎤`;

      await ctx.editMessageText(message, {
        parse_mode: 'Markdown',
        reply_markup: {
          inline_keyboard: [
            [
              {
                text: `🔄 ${primaryLang.flag} ⇄ ${secondaryLang.flag} Поміняти мови`,
                callback_data: 'switch_languages'
              }
            ],
            [
              {
                text: '⚙️ Налаштування',
                callback_data: 'open_settings'
              },
              {
                text: '📊 Мої ліміти',
                callback_data: 'show_limits'
              }
            ]
          ]
        }
      });
      
      await ctx.answerCbQuery(`🔄 Переключено на ${primaryLang.flag} ⇄ ${secondaryLang.flag}`);
    } catch (error) {
      logger.error('Error in handleSwitchAndSpeak:', error);
      await ctx.answerCbQuery('❌ Виникла помилка при переключенні');
    }
  }

  /**
   * Handle showing user limits
   */
  async handleShowLimits(ctx) {
    try {
      const userId = ctx.from.id;
      logger.info(`User ${userId} requested limits via callback`);

      const user = await databaseService.getUserByTelegramId(userId);
      if (!user) {
        await ctx.answerCbQuery('❌ Помилка: користувач не знайден');
        return;
      }

      const userStats = await databaseService.getUserStats(user._id);
      const { tokenLimits } = require('../config/config').config;

      // Get current limits based on subscription
      const limits = user.getCurrentLimits();

      // Calculate remaining limits
      const dailyRemaining = Math.max(0, limits.dailyLimit - userStats.tokenUsage.dailyUsed);
      const monthlyRemaining = Math.max(0, limits.monthlyLimit - userStats.tokenUsage.monthlyUsed);

      // Calculate percentages
      const dailyPercent = Math.round((userStats.tokenUsage.dailyUsed / limits.dailyLimit) * 100);
      const monthlyPercent = Math.round((userStats.tokenUsage.monthlyUsed / limits.monthlyLimit) * 100);

      // Progress bars
      const dailyBar = this.generateProgressBar(dailyPercent, 20);
      const monthlyBar = this.generateProgressBar(monthlyPercent, 20);

      const limitsMessage = `📊 **Ваші ліміти використання**

👤 **Підписка:** ${userStats.subscription.type === 'premium' ? '💎 Premium' : '🆓 Безкоштовна'}

📈 **Денний ліміт:**
${dailyBar} ${dailyPercent}%
• Використано: ${userStats.tokenUsage.dailyUsed}
• Залишилось: ${dailyRemaining}
• Всього: ${limits.dailyLimit}

📊 **Місячний ліміт:**
${monthlyBar} ${monthlyPercent}%
• Використано: ${userStats.tokenUsage.monthlyUsed}
• Залишилось: ${monthlyRemaining}
• Всього: ${limits.monthlyLimit}

💡 **Статистика:**
• Всього перекладів: ${userStats.stats.totalTranslations}
• Всього токенів: ${userStats.tokenUsage.totalUsed}

${userStats.subscription.type === 'free' ? '\n💎 Преміум підписка дає x10 більше лімітів!' : ''}`;

      // Generate keyboard based on subscription
      let keyboard = [];
      if (userStats.subscription.type === 'premium') {
        keyboard = [
          [
            {
              text: '⚙️ Налаштування',
              callback_data: 'open_settings'
            },
            {
              text: '📖 Довідка',
              callback_data: 'show_help'
            }
          ]
        ];
      } else {
        keyboard = [
          [
            {
              text: '💎 Преміум',
              callback_data: 'upgrade_premium'
            },
            {
              text: '⚙️ Налаштування',
              callback_data: 'open_settings'
            }
          ]
        ];
      }

      await ctx.editMessageText(limitsMessage, {
        parse_mode: 'Markdown',
        reply_markup: {
          inline_keyboard: keyboard
        }
      });

      await ctx.answerCbQuery();
    } catch (error) {
      logger.error('Error in handleShowLimits:', error);
      await ctx.answerCbQuery('❌ Виникла помилка при завантаженні лімітів');
    }
  }

  /**
   * Handle upgrade to premium request
   */
  async handleUpgradePremium(ctx) {
    try {
      const premiumMessage = `💎 **Преміум підписка AI Translator Bot**

🚀 **Переваги преміум:**
✅ **Автоматичне розпізнавання мови** (GPT + Whisper)
✅ **Зворотний переклад** для перевірки якості
✅ **x10 більше лімітів** токенів (100,000/день)
✅ **Покращена точність** розпізнавання мови
✅ **Пріоритетна підтримка**

💰 **Тарифи:**
• Місяць: $9.99
• Рік: $99.99 (економія 17%)

📞 **Для підключення преміум звертайтесь до розробника.**`;

      await ctx.editMessageText(premiumMessage, {
        parse_mode: 'Markdown',
        reply_markup: {
          inline_keyboard: [
            [
              {
                text: '📊 Мої ліміти',
                callback_data: 'show_limits'
              },
              {
                text: '⚙️ Налаштування',
                callback_data: 'open_settings'
              }
            ]
          ]
        }
      });

      await ctx.answerCbQuery('💎 Інформація про преміум');
    } catch (error) {
      logger.error('Error in handleUpgradePremium:', error);
      await ctx.answerCbQuery('❌ Виникла помилка');
    }
  }

  /**
   * Handle setting voice language for free users
   */
  async handleSetVoiceLanguage(ctx, callbackData) {
    try {
      const languageCode = callbackData.replace('set_voice_lang_', '');
      const userId = ctx.from.id;
      
      // Get user
      const user = await databaseService.getUserByTelegramId(userId);
      if (!user) {
        await ctx.answerCbQuery('❌ Помилка: користувач не знайден');
        return;
      }

      // Check if user is free
      if (user.isPremium) {
        await ctx.answerCbQuery('💎 Преміум користувачі мають автоматичне розпізнавання мови');
        return;
      }

      // Set voice language
      user.setVoiceInputLanguage(languageCode);
      await user.save();

      const languageInfo = languageService.getLanguageInfo(languageCode);
      const targetLang = languageCode === user.languages.primaryLanguage ? 
        user.languages.secondaryLanguage : user.languages.primaryLanguage;
      const targetLangInfo = languageService.getLanguageInfo(targetLang);

      const message = `✅ **Мову диктування встановлено!**

🎤 **Диктувати:** ${languageInfo.flag} ${languageInfo.name}
🌍 **Перекладати на:** ${targetLangInfo.flag} ${targetLangInfo.name}

🎯 **Тепер надішліть голосове повідомлення**
⏱️ *Налаштування діють 5 хвилин*`;

      await ctx.editMessageText(message, {
        parse_mode: 'Markdown',
        reply_markup: {
          inline_keyboard: [
            [
              {
                text: '🔄 Змінити мову',
                callback_data: `set_voice_lang_${targetLang}`
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

      await ctx.answerCbQuery(`✅ Диктувати: ${languageInfo.name}`);
    } catch (error) {
      logger.error('Error in handleSetVoiceLanguage:', error);
      await ctx.answerCbQuery('❌ Виникла помилка');
    }
  }

  /**
   * Handle choosing voice language
   */
  async handleChooseVoiceLanguage(ctx) {
    try {
      const userId = ctx.from.id;
      
      // Get user
      const user = await databaseService.getUserByTelegramId(userId);
      if (!user) {
        await ctx.answerCbQuery('❌ Помилка: користувач не знайден');
        return;
      }

      // Check if user is free
      if (user.isPremium) {
        await ctx.answerCbQuery('💎 Преміум користувачі мають автоматичне розпізнавання мови');
        return;
      }

      const audioHandler = require('./audioHandler');
      await audioHandler.showLanguageSelectionForFreeUser(ctx, user);
      await ctx.answerCbQuery('🎯 Оберіть мову диктування');
    } catch (error) {
      logger.error('Error in handleChooseVoiceLanguage:', error);
      await ctx.answerCbQuery('❌ Виникла помилка');
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
      } else if (data === 'show_limits') {
        await this.handleShowLimits(ctx);
      } else if (data === 'upgrade_premium') {
        await this.handleUpgradePremium(ctx);
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
      } else if (data.startsWith('set_voice_lang_')) {
        await this.handleSetVoiceLanguage(ctx, data);
      } else if (data === 'choose_voice_language') {
        await this.handleChooseVoiceLanguage(ctx);
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