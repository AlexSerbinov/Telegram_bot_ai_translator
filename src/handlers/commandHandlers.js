const languageService = require('../services/languageService');
const databaseService = require('../services/databaseService');
const logger = require('../utils/logger');

class CommandHandlers {
  
  /**
   * Handle /start command
   */
  async handleStart(ctx) {
    try {
      const userId = ctx.from.id;
      const userName = ctx.from.first_name || 'Friend';
      
      logger.info(`User ${userId} started the bot`);
      
      const welcomeMessage = `🤖 Привіт, ${userName}! 

Я AI Translator Bot - твій особистий помічник для перекладу голосових повідомлень.

🤖 **Як це працює:**
1. Оберіть дві мови у налаштуваннях
2. Надішліть голосове повідомлення будь-якою з цих мов
3. Система автоматично розпізнає мову та перекладе на іншу
4. Отримаєте переклад з верифікацією якості

⚙️ Спочатку налаштуйте дві мови командою /settings`;

      await ctx.reply(welcomeMessage, {
        reply_markup: {
          inline_keyboard: [
            [
              {
                text: '⚙️ Налаштувати мови',
                callback_data: 'open_settings'
              }
            ],
            [
              {
                text: '📊 Мої ліміти',
                callback_data: 'show_limits'
              }
            ]
          ]
        }
      });
    } catch (error) {
      logger.error('Error in handleStart:', error);
      await ctx.reply('❌ Виникла помилка при запуску. Спробуйте ще раз.');
    }
  }

  /**
   * Handle /settings command
   */
  async handleSettings(ctx) {
    try {
      const userId = ctx.from.id;
      logger.info(`User ${userId} opened settings`);
      
      const currentSettings = await languageService.formatCurrentSettings(userId);
      const keyboard = await languageService.generateSettingsKeyboard(userId);
      
      const message = `⚙️ **Налаштування перекладача**

${currentSettings}

Виберіть, що хочете змінити:`;

      await ctx.reply(message, {
        parse_mode: 'Markdown',
        reply_markup: keyboard
      });
    } catch (error) {
      logger.error('Error in handleSettings:', error);
      await ctx.reply('❌ Виникла помилка при відкритті налаштувань.');
    }
  }

  /**
   * Handle /menu command
   */
  async handleMenu(ctx) {
    try {
      logger.info(`User ${ctx.from.id} opened main menu`);
      
      const menuMessage = `🤖 **Головне меню AI Translator Bot**

Оберіть дію:`;

      await ctx.reply(menuMessage, {
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
                text: '📊 Мої ліміти',
                callback_data: 'show_limits'
              },
              {
                text: '📖 Довідка',
                callback_data: 'show_help'
              }
            ]
          ]
        }
      });
    } catch (error) {
      logger.error('Error in handleMenu:', error);
      await ctx.reply('❌ Виникла помилка при відкритті меню.');
    }
  }

  /**
   * Handle /stats command
   */
  async handleStats(ctx) {
    try {
      const userId = ctx.from.id;
      logger.info(`User ${userId} requested stats`);

      const user = await databaseService.getUserByTelegramId(userId);
      if (!user) {
        await ctx.reply('❌ Помилка: користувач не знайден. Спробуйте команду /start');
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

      const statsMessage = `📊 **Ваша статистика**

👤 **Підписка:** ${userStats.subscription.type === 'premium' ? '💎 Premium' : '🆓 Безкоштовна'}

📈 **Використання токенів:**
• Сьогодні: ${userStats.tokenUsage.dailyUsed} / ${tokenLimits.freeTierDaily} (${dailyPercent}%)
• Цього місяця: ${userStats.tokenUsage.monthlyUsed} / ${tokenLimits.freeTierMonthly} (${monthlyPercent}%)
• Всього: ${userStats.tokenUsage.totalUsed}

⏳ **Залишилось:**
• Сьогодні: ${dailyRemaining} токенів
• Цього місяця: ${monthlyRemaining} токенів

📊 **Активність:**
• Всього перекладів: ${userStats.stats.totalTranslations}
• Всього чатів: ${userStats.stats.totalChats}

${userStats.subscription.type === 'free' ? '\n💎 Розглядайте можливість преміум підписки для необмежених перекладів!' : ''}`;

      await ctx.reply(statsMessage, {
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
    } catch (error) {
      logger.error('Error in handleStats:', error);
      await ctx.reply('❌ Виникла помилка при отриманні статистики.');
    }
  }

  /**
   * Handle /limits command
   */
  async handleLimits(ctx) {
    try {
      const userId = ctx.from.id;
      logger.info(`User ${userId} requested limits via command`);

      const user = await databaseService.getUserByTelegramId(userId);
      if (!user) {
        await ctx.reply('❌ Помилка: користувач не знайден. Спробуйте команду /start');
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

      await ctx.reply(limitsMessage, {
        parse_mode: 'Markdown',
        reply_markup: {
          inline_keyboard: [
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
          ]
        }
      });
    } catch (error) {
      logger.error('Error in handleLimits:', error);
      await ctx.reply('❌ Виникла помилка при отриманні лімітів.');
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
   * Handle /help command
   */
  async handleHelp(ctx) {
    try {
      logger.info(`User ${ctx.from.id} requested help`);
      
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
🇺🇦 Українська
🇺🇸 English  
🇬🇪 ქართული
🇮🇩 Bahasa Indonesia
🇷🇺 Русский

📝 **Як користуватися:**
1. Налаштуйте дві мови в /settings
2. Надішліть голосове повідомлення будь-якою з цих мов
3. Система автоматично розпізнає мову та перекладе на іншу
4. Використовуйте кнопку Switch для зміни мов

❓ Питання? Напишіть розробнику.`;

      await ctx.reply(helpMessage, {
        parse_mode: 'Markdown'
      });
    } catch (error) {
      logger.error('Error in handleHelp:', error);
      await ctx.reply('❌ Виникла помилка при показі довідки.');
    }
  }

  /**
   * Handle unknown text messages
   */
  async handleUnknownText(ctx) {
    try {
      const message = `🎤 Надішліть **голосове повідомлення** для перекладу.

Якщо потрібна допомога, використовуйте /help
Для налаштування мов: /settings`;

      await ctx.reply(message, {
        parse_mode: 'Markdown',
        reply_markup: {
          inline_keyboard: [
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
          ]
        }
      });
    } catch (error) {
      logger.error('Error in handleUnknownText:', error);
    }
  }

  /**
   * Handle /go_premium command (development only)
   */
  async handleGoPremium(ctx) {
    try {
      const userId = ctx.from.id;
      logger.info(`DEV: User ${userId} requested premium upgrade`);
      
      const user = await databaseService.getUserByTelegramId(userId);
      if (!user) {
        await ctx.reply('❌ Помилка: користувач не знайден.');
        return;
      }

      // Set premium subscription
      user.subscription.type = 'premium';
      user.subscription.expiresAt = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000); // 1 year
      await user.save();

      await ctx.reply('🎉 Ви отримали преміум статус! 👑\n\n✅ Автоматичне розпізнавання мови\n✅ Зворотний переклад\n✅ x10 більше лімітів');
    } catch (error) {
      logger.error('Error in handleGoPremium:', error);
      await ctx.reply('❌ Виникла помилка.');
    }
  }

  /**
   * Handle /go_free command (development only)
   */
  async handleGoFree(ctx) {
    try {
      const userId = ctx.from.id;
      logger.info(`DEV: User ${userId} requested free downgrade`);
      
      const user = await databaseService.getUserByTelegramId(userId);
      if (!user) {
        await ctx.reply('❌ Помилка: користувач не знайден.');
        return;
      }

      // Set free subscription
      user.subscription.type = 'free';
      user.subscription.expiresAt = null;
      await user.save();

      await ctx.reply('🆓 Ви перейшли на безкоштовний тариф.\n\n⚠️ Преміум функції недоступні:\n• Автоматичне розпізнавання мови\n• Зворотний переклад\n• Збільшені ліміти');
    } catch (error) {
      logger.error('Error in handleGoFree:', error);
      await ctx.reply('❌ Виникла помилка.');
    }
  }
}

module.exports = new CommandHandlers(); 