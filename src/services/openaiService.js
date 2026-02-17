const logger = require('../utils/logger');
const elevenLabsService = require('./elevenLabsService');
const geminiService = require('./geminiService');
const groqService = require('./groqService');
const { config } = require('../config/config');

class OpenAIService {
  constructor() {}

  /**
   * Get the active translation service based on config
   */
  get translationService() {
    return config.translation.provider === 'groq' ? groqService : geminiService;
  }

  /**
   * Convert speech to text using ElevenLabs Scribe V2
   */
  async speechToText(audioFilePath, language = 'auto') {
    return elevenLabsService.speechToText(audioFilePath, language);
  }

  /**
   * Detect language of text using Gemini
   */
  async detectTextLanguage(text, expectedLanguages = ['uk', 'en', 'ka', 'id', 'ru']) {
    return this.translationService.detectTextLanguage(text, expectedLanguages);
  }

  /**
   * Translate text using Gemini
   */
  async translateText(text, fromLanguage, toLanguage) {
    return this.translationService.translateText(text, fromLanguage, toLanguage);
  }

  /**
   * Perform back-translation for verification
   */
  async backTranslate(translatedText, originalLanguage, translationLanguage) {
    return this.translationService.backTranslate(translatedText, originalLanguage, translationLanguage);
  }

  /**
   * Determine target language based on detected language and user's language pair
   */
  determineTargetLanguage(detectedLanguage, primaryLang, secondaryLang) {
    // detectedLanguage is already normalized by speechToText method
    
    // If detected language matches primary, translate to secondary
    if (detectedLanguage === primaryLang) {
      return secondaryLang;
    }
    
    // If detected language matches secondary, translate to primary  
    if (detectedLanguage === secondaryLang) {
      return primaryLang;
    }
    
    // If detected language doesn't match either, default to translating to primary
    logger.warn(`Detected language ${detectedLanguage} doesn't match user's languages (${primaryLang}, ${secondaryLang}). Defaulting to ${primaryLang}`);
    return primaryLang;
  }

  /**
   * Complete translation flow with automatic language detection (Premium)
   */
  async completeTranslationAuto(audioFilePath, primaryLanguage, secondaryLanguage, isPremium = false) {
    try {
      logger.info(`Starting translation flow - ${isPremium ? '👑 Premium' : '🆓 Free'} user`);
      
      // 1. Speech to text with language detection via Whisper
      const speechResult = await this.speechToText(audioFilePath, 'auto');
      const originalText = speechResult.text;
      const whisperDetectedLanguage = speechResult.detectedLanguage;
      
      logger.info(`Whisper detected: ${whisperDetectedLanguage}`);
      
      let finalDetectedLanguage = whisperDetectedLanguage;
      let gptDetectedLanguage = null;
      let detectionMethod = 'Whisper Only';
      
      // 2. Premium users get GPT language detection for better accuracy
      if (isPremium) {
        const userLanguages = [primaryLanguage, secondaryLanguage];
        gptDetectedLanguage = await this.detectTextLanguage(originalText, userLanguages);
        logger.info(`GPT detected: ${gptDetectedLanguage}`);
        
                // 3. Choose the most reliable language detection (GPT has priority for better accuracy)
        detectionMethod = 'Premium: Whisper + GPT';
        
        // If both Whisper and GPT agree, use that
        if (whisperDetectedLanguage === gptDetectedLanguage) {
          finalDetectedLanguage = whisperDetectedLanguage;
          logger.info(`✅ Both models agree: ${finalDetectedLanguage}`);
        }
        // If GPT detected one of user's languages, trust GPT (higher priority)
        else if (userLanguages.includes(gptDetectedLanguage)) {
          finalDetectedLanguage = gptDetectedLanguage;
          logger.info(`🧠 Using GPT detection (${gptDetectedLanguage}) - GPT has priority for text analysis`);
        }
        // If only Whisper detected one of user's languages, use Whisper
        else if (userLanguages.includes(whisperDetectedLanguage)) {
          finalDetectedLanguage = whisperDetectedLanguage;
          logger.info(`🎤 Using Whisper detection (${whisperDetectedLanguage}) - only Whisper detected user language`);
        }
        // Neither detected user's languages, but GPT is generally more accurate for text analysis
        else {
          finalDetectedLanguage = gptDetectedLanguage;
          logger.info(`🔍 Using GPT detection (${gptDetectedLanguage}) over Whisper (${whisperDetectedLanguage}) - GPT better for text analysis`);
        }
      } else {
        // Free users only get Whisper detection
        logger.info(`🆓 Free user: Using Whisper detection only: ${finalDetectedLanguage}`);
      }
      
      // 4. Determine target language
      const targetLanguage = this.determineTargetLanguage(finalDetectedLanguage, primaryLanguage, secondaryLanguage);
      
      logger.info(`Final: ${finalDetectedLanguage} → ${targetLanguage}`);
      
      // 5. Translate
      const translatedText = await this.translateText(originalText, finalDetectedLanguage, targetLanguage);
      
      // 6. Back-translate for verification (Premium feature only)
      let backTranslation = null;
      let additionalTokens = 0;
      
      if (isPremium) {
        backTranslation = await this.backTranslate(translatedText, targetLanguage, finalDetectedLanguage);
        additionalTokens = 10; // GPT language detection + back-translation tokens
        logger.info('👑 Premium: Back-translation completed');
      } else {
        logger.info('🆓 Free user: Back-translation not available');
      }
      
      const result = {
        original: originalText,
        translated: translatedText,
        backTranslation: backTranslation,
        detectedLanguage: finalDetectedLanguage,
        targetLanguage: targetLanguage,
        whisperDetection: whisperDetectedLanguage,
        gptDetection: gptDetectedLanguage,
        detectionMethod: detectionMethod,
        isPremium: isPremium,
        tokensUsed: this.estimateTokenUsage(originalText, translatedText) + additionalTokens
      };
      
      logger.info(`${isPremium ? '👑 Premium' : '🆓 Free'} translation flow finished successfully`);
      return result;
    } catch (error) {
      logger.error('Error in automatic translation flow:', error);
      throw error;
    }
  }

  /**
   * Complete translation flow for Free users (manual language selection)
   */
  async completeTranslationManual(audioFilePath, fromLanguage, toLanguage) {
    try {
      logger.info('🆓 Starting manual translation flow for Free user');
      
      // 1. Speech to text (with specified language for better accuracy)
      const speechResult = await this.speechToText(audioFilePath, fromLanguage);
      const originalText = speechResult.text;
      
      // 2. Translate
      const translatedText = await this.translateText(originalText, fromLanguage, toLanguage);
      
      const result = {
        original: originalText,
        translated: translatedText,
        backTranslation: null, // Not available for free users
        detectedLanguage: fromLanguage, // User manually selected
        targetLanguage: toLanguage,
        whisperDetection: fromLanguage,
        gptDetection: null, // Not used for free users
        detectionMethod: 'Manual Selection',
        isPremium: false,
        tokensUsed: this.estimateTokenUsage(originalText, translatedText)
      };
      
      logger.info('🆓 Manual translation flow finished successfully');
      return result;
    } catch (error) {
      logger.error('Error in manual translation flow:', error);
      throw error;
    }
  }

  /**
   * Complete translation flow (legacy method for backward compatibility)
   */
  async completeTranslation(audioFilePath, fromLanguage, toLanguage) {
    try {
      logger.info('Starting complete translation flow (legacy)');
      
      // 1. Speech to text
      const speechResult = await this.speechToText(audioFilePath, fromLanguage);
      const originalText = speechResult.text;
      
      // 2. Translate
      const translatedText = await this.translateText(originalText, fromLanguage, toLanguage);
      
      // 3. Back-translate for verification
      const backTranslation = await this.backTranslate(translatedText, fromLanguage, toLanguage);
      
      const result = {
        original: originalText,
        translated: translatedText,
        backTranslation: backTranslation,
        fromLanguage,
        toLanguage,
        tokensUsed: this.estimateTokenUsage(originalText, translatedText)
      };
      
      logger.info('Complete translation flow finished successfully');
      return result;
    } catch (error) {
      logger.error('Error in complete translation flow:', error);
      throw error;
    }
  }

  /**
   * Estimate token usage for tracking
   */
  estimateTokenUsage(originalText, translatedText) {
    // Rough estimation: ~1 token per 4 characters
    const originalTokens = Math.ceil(originalText.length / 4);
    const translatedTokens = Math.ceil(translatedText.length / 4);
    
    // STT, translation, back-translation, plus some overhead
    return originalTokens + translatedTokens * 2 + 50;
  }
}

module.exports = new OpenAIService(); 