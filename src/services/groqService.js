const { config } = require('../config/config');
const logger = require('../utils/logger');

class GroqService {
  constructor() {
    this.apiUrl = 'https://api.groq.com/openai/v1/chat/completions';
  }

  /**
   * Call Groq API (OpenAI-compatible)
   */
  async generate(systemPrompt, userMessage) {
    const response = await fetch(this.apiUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${config.groq.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: config.groq.model,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userMessage },
        ],
        temperature: 0.3,
      }),
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`Groq API error ${response.status}: ${error}`);
    }

    const data = await response.json();
    return data.choices[0].message.content.trim();
  }

  /**
   * Detect language of text
   */
  async detectTextLanguage(text, expectedLanguages = ['uk', 'en', 'ka', 'id', 'ru']) {
    try {
      logger.info('[Groq] Detecting language of text');

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
        logger.info(`[Groq] Detected language: ${languageCode}`);
        return languageCode;
      } else {
        logger.warn(`[Groq] Unexpected language: ${result}, falling back to ${expectedLanguages[0]}`);
        return expectedLanguages[0];
      }
    } catch (error) {
      logger.error('[Groq] Error in language detection:', error);
      return expectedLanguages[0];
    }
  }

  /**
   * Translate text
   */
  async translateText(text, fromLanguage, toLanguage) {
    try {
      logger.info(`[Groq] Translating from ${fromLanguage} to ${toLanguage}`);

      const translation = await this.generate(
        `You are a professional translation engine.
Translate the user text into ${toLanguage}.
The expected source language is ${fromLanguage}, but if the text is actually in another language (or mixed), still translate it into ${toLanguage}.
Never refuse, never ask clarifying questions, and never mention language mismatch.
Return only the translation text with no explanations, labels, or quotes.`,
        text
      );

      logger.info('[Groq] Translation successful');
      return translation;
    } catch (error) {
      logger.error('[Groq] Error in translation:', error);
      throw error;
    }
  }

  /**
   * Back-translate for verification
   */
  async backTranslate(translatedText, originalLanguage, translationLanguage) {
    try {
      logger.info(`[Groq] Back-translating from ${translationLanguage} to ${originalLanguage}`);
      return await this.translateText(translatedText, translationLanguage, originalLanguage);
    } catch (error) {
      logger.error('[Groq] Error in back-translation:', error);
      throw error;
    }
  }
}

module.exports = new GroqService();
