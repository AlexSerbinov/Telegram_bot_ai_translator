const OpenAI = require('openai');
const fs = require('fs-extra');
const { config } = require('../config/config');
const logger = require('../utils/logger');

class OpenAIService {
  constructor() {
    this.client = new OpenAI({
      apiKey: config.openai.apiKey,
    });
    
    // Mapping between Whisper language names and our language codes
    this.whisperLanguageMap = {
      'ukrainian': 'uk',
      'english': 'en',
      'georgian': 'ka',
      'indonesian': 'id',
      'russian': 'ru',
      // Alternative names
      'uk': 'uk',
      'en': 'en', 
      'ka': 'ka',
      'id': 'id',
      'ru': 'ru'
    };
  }

  /**
   * Normalize Whisper language name to our language code
   */
  normalizeLanguage(whisperLanguage) {
    const normalized = this.whisperLanguageMap[whisperLanguage.toLowerCase()];
    if (!normalized) {
      logger.warn(`Unknown Whisper language: ${whisperLanguage}, defaulting to 'uk'`);
      return 'uk';
    }
    return normalized;
  }

  /**
   * Convert speech to text using Whisper with automatic language detection
   */
  async speechToText(audioFilePath, language = 'auto') {
    try {
      logger.info(`Converting speech to text with language detection`);
      
      const transcription = await this.client.audio.transcriptions.create({
        file: fs.createReadStream(audioFilePath),
        model: config.openai.models.whisper,
        language: language === 'auto' ? undefined : language,
        response_format: 'verbose_json' // Get language info
      });

      const result = {
        text: transcription.text,
        detectedLanguage: this.normalizeLanguage(transcription.language)
      };

      logger.info(`Speech-to-text successful. Detected language: ${transcription.language} -> ${result.detectedLanguage}`);
      return result;
    } catch (error) {
      logger.error('Error in speech-to-text conversion:', error);
      throw error;
    }
  }

  /**
   * Detect language of text using GPT (as backup to Whisper)
   */
  async detectTextLanguage(text, expectedLanguages = ['uk', 'en', 'ka', 'id', 'ru']) {
    try {
      logger.info(`Detecting language of text using GPT`);
      
      const languageNames = expectedLanguages.map(code => {
        const info = require('../config/config').config.languages[code];
        return `${code} (${info.name})`;
      }).join(', ');
      
      const response = await this.client.chat.completions.create({
        model: config.openai.models.gpt,
        messages: [
          {
            role: 'system',
            content: `You are a language detection expert. Analyze the given text and determine which language it is written in. Respond with ONLY the language code from this list: ${languageNames}. If unsure, respond with the most likely language code.`
          },
          {
            role: 'user',
            content: `Detect the language of this text: "${text}"`
          }
        ],
        temperature: 0.1,
        max_tokens: 10
      });

      const detectedLanguage = response.choices[0].message.content.trim().toLowerCase();
      
      // Extract just the language code (in case GPT returned more than just the code)
      const languageCode = detectedLanguage.split(' ')[0];
      
      // Validate it's one of our supported languages
      if (expectedLanguages.includes(languageCode)) {
        logger.info(`GPT detected language: ${languageCode}`);
        return languageCode;
      } else {
        logger.warn(`GPT returned unexpected language: ${detectedLanguage}, falling back to first expected language`);
        return expectedLanguages[0];
      }
    } catch (error) {
      logger.error('Error in GPT language detection:', error);
      return expectedLanguages[0]; // Fallback to first expected language
    }
  }

  /**
   * Translate text using GPT
   */
  async translateText(text, fromLanguage, toLanguage) {
    try {
      logger.info(`Translating from ${fromLanguage} to ${toLanguage}`);
      
      const response = await this.client.chat.completions.create({
        model: config.openai.models.gpt,
        messages: [
          {
            role: 'system',
            content: `You are a professional translator. Translate the following text from ${fromLanguage} to ${toLanguage}. Return only the translation without any additional text or explanations.`
          },
          {
            role: 'user',
            content: text
          }
        ],
        temperature: 0.1,
        max_tokens: 1000
      });

      const translation = response.choices[0].message.content.trim();
      logger.info('Translation successful');
      return translation;
    } catch (error) {
      logger.error('Error in translation:', error);
      throw error;
    }
  }

  /**
   * Perform back-translation for verification
   */
  async backTranslate(translatedText, originalLanguage, translationLanguage) {
    try {
      logger.info(`Back-translating from ${translationLanguage} to ${originalLanguage}`);
      
      const backTranslation = await this.translateText(
        translatedText, 
        translationLanguage, 
        originalLanguage
      );
      
      logger.info('Back-translation successful');
      return backTranslation;
    } catch (error) {
      logger.error('Error in back-translation:', error);
      throw error;
    }
  }

  /**
   * Convert text to speech
   */
  async textToSpeech(text, language = 'en', outputPath) {
    try {
      logger.info(`Converting text to speech for language: ${language}`);
      
      const mp3 = await this.client.audio.speech.create({
        model: config.openai.models.tts,
        voice: 'alloy', // You can make this configurable
        input: text,
        speed: 1.0
      });

      const buffer = Buffer.from(await mp3.arrayBuffer());
      await fs.writeFile(outputPath, buffer);
      
      logger.info('Text-to-speech conversion successful');
      return outputPath;
    } catch (error) {
      logger.error('Error in text-to-speech conversion:', error);
      throw error;
    }
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