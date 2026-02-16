const { GoogleGenAI } = require('@google/genai');
const { config } = require('../config/config');
const logger = require('../utils/logger');

class GeminiService {
  constructor() {
    this.ai = new GoogleGenAI({ apiKey: config.gemini.apiKey });
  }

  /**
   * Generate text using Gemini
   */
  async generate(systemPrompt, userMessage) {
    const response = await this.ai.models.generateContent({
      model: config.gemini.model,
      contents: [
        { role: 'user', parts: [{ text: `${systemPrompt}\n\n${userMessage}` }] }
      ],
    });
    return response.text.trim();
  }

  /**
   * Detect language of text
   */
  async detectTextLanguage(text, expectedLanguages = ['uk', 'en', 'ka', 'id', 'ru']) {
    try {
      logger.info('[Gemini] Detecting language of text');

      const languageNames = expectedLanguages.map(code => {
        const info = config.languages[code];
        return `${code} (${info.name})`;
      }).join(', ');

      const result = await this.generate(
        `You are a language detection expert. Analyze the given text and determine which language it is written in. Respond with ONLY the language code from this list: ${languageNames}. If unsure, respond with the most likely language code.`,
        `Detect the language of this text: "${text}"`
      );

      const languageCode = result.toLowerCase().split(' ')[0];

      if (expectedLanguages.includes(languageCode)) {
        logger.info(`[Gemini] Detected language: ${languageCode}`);
        return languageCode;
      } else {
        logger.warn(`[Gemini] Unexpected language: ${result}, falling back to ${expectedLanguages[0]}`);
        return expectedLanguages[0];
      }
    } catch (error) {
      logger.error('[Gemini] Error in language detection:', error);
      return expectedLanguages[0];
    }
  }

  /**
   * Translate text
   */
  async translateText(text, fromLanguage, toLanguage) {
    try {
      logger.info(`[Gemini] Translating from ${fromLanguage} to ${toLanguage}`);

      const translation = await this.generate(
        `You are a professional translator. Translate the following text from ${fromLanguage} to ${toLanguage}. Return only the translation without any additional text or explanations.`,
        text
      );

      logger.info('[Gemini] Translation successful');
      return translation;
    } catch (error) {
      logger.error('[Gemini] Error in translation:', error);
      throw error;
    }
  }

  /**
   * Back-translate for verification
   */
  async backTranslate(translatedText, originalLanguage, translationLanguage) {
    try {
      logger.info(`[Gemini] Back-translating from ${translationLanguage} to ${originalLanguage}`);
      return await this.translateText(translatedText, translationLanguage, originalLanguage);
    } catch (error) {
      logger.error('[Gemini] Error in back-translation:', error);
      throw error;
    }
  }
}

module.exports = new GeminiService();
