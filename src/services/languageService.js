const { config } = require('../config/config');
const logger = require('../utils/logger');
const databaseService = require('./databaseService');

class LanguageService {
  constructor() {
    this.languages = config.languages;
  }

  /**
   * Get all supported languages
   */
  getSupportedLanguages() {
    return Object.entries(this.languages).map(([code, info]) => ({
      code,
      ...info
    }));
  }

  /**
   * Get language info by code
   */
  getLanguageInfo(languageCode) {
    return this.languages[languageCode] || null;
  }

  /**
   * Set user language preferences (two languages for auto-detection)
   */
  async setUserLanguages(telegramId, primaryLanguage, secondaryLanguage) {
    try {
      const user = await databaseService.getUserByTelegramId(telegramId);
      if (user) {
        await databaseService.updateUserLanguages(user._id, primaryLanguage, secondaryLanguage);
        logger.info(`Updated language settings for user ${telegramId}: ${primaryLanguage} <-> ${secondaryLanguage}`);
      }
    } catch (error) {
      logger.error('Error setting user languages:', error);
      throw error;
    }
  }

  /**
   * Get user language preferences
   */
  async getUserLanguages(telegramId) {
    try {
      const user = await databaseService.getUserByTelegramId(telegramId);
      return user ? user.languages : {
        primaryLanguage: 'uk',   // Default
        secondaryLanguage: 'es'  // Default
      };
    } catch (error) {
      logger.error('Error getting user languages:', error);
      return {
        primaryLanguage: 'uk',   // Default
        secondaryLanguage: 'es'  // Default
      };
    }
  }

  /**
   * Switch user languages (swap primary and secondary)
   */
  async switchUserLanguages(telegramId) {
    try {
      const currentSettings = await this.getUserLanguages(telegramId);
      const newSettings = {
        primaryLanguage: currentSettings.secondaryLanguage,
        secondaryLanguage: currentSettings.primaryLanguage
      };
      
      await this.setUserLanguages(telegramId, newSettings.primaryLanguage, newSettings.secondaryLanguage);
      logger.info(`Switched languages for user ${telegramId}: ${newSettings.primaryLanguage} <-> ${newSettings.secondaryLanguage}`);
      
      return newSettings;
    } catch (error) {
      logger.error('Error switching user languages:', error);
      throw error;
    }
  }

  /**
   * Generate inline keyboard for language selection
   */
  generateLanguageKeyboard(type = 'from') {
    const languages = this.getSupportedLanguages();
    const keyboard = [];
    
    // Create rows with 2 languages per row
    for (let i = 0; i < languages.length; i += 2) {
      const row = [];
      
      row.push({
        text: `${languages[i].flag} ${languages[i].name}`,
        callback_data: `lang_${type}_${languages[i].code}`
      });
      
      if (i + 1 < languages.length) {
        row.push({
          text: `${languages[i + 1].flag} ${languages[i + 1].name}`,
          callback_data: `lang_${type}_${languages[i + 1].code}`
        });
      }
      
      keyboard.push(row);
    }
    
    return {
      inline_keyboard: keyboard
    };
  }

  /**
   * Generate current settings keyboard
   */
  async generateSettingsKeyboard(telegramId) {
    const settings = await this.getUserLanguages(telegramId);
    const primaryLang = this.getLanguageInfo(settings.primaryLanguage);
    const secondaryLang = this.getLanguageInfo(settings.secondaryLanguage);
    
    return {
      inline_keyboard: [
        [
          {
            text: `1️⃣ Змінити першу мову (${primaryLang.flag} ${primaryLang.name})`,
            callback_data: 'change_primary_language'
          }
        ],
        [
          {
            text: `2️⃣ Змінити другу мову (${secondaryLang.flag} ${secondaryLang.name})`,
            callback_data: 'change_secondary_language'
          }
        ],
        [
          {
            text: '🔄 Поміняти мови місцями',
            callback_data: 'switch_languages'
          }
        ],
        [
          {
            text: '✅ Готово',
            callback_data: 'settings_done'
          }
        ]
      ]
    };
  }

  /**
   * Generate switch keyboard after translation
   */
  async generateSwitchKeyboard(telegramId) {
    const settings = await this.getUserLanguages(telegramId);
    const primaryLang = this.getLanguageInfo(settings.primaryLanguage);
    const secondaryLang = this.getLanguageInfo(settings.secondaryLanguage);
    
    return {
      inline_keyboard: [
        [
          {
            text: `🔄 ${primaryLang.flag} ⇄ ${secondaryLang.flag} Switch`,
            callback_data: 'switch_and_speak'
          }
        ]
      ]
    };
  }

  /**
   * Format current settings for display
   */
  async formatCurrentSettings(telegramId) {
    const settings = await this.getUserLanguages(telegramId);
    const primaryLang = this.getLanguageInfo(settings.primaryLanguage);
    const secondaryLang = this.getLanguageInfo(settings.secondaryLanguage);
    
    return `🤖 **Автоматичне розпізнавання мови**\n\n1️⃣ ${primaryLang.flag} ${primaryLang.name}\n2️⃣ ${secondaryLang.flag} ${secondaryLang.name}\n\n💡 Система автоматично визначить мову та перекладе на іншу`;
  }
}

module.exports = new LanguageService(); 