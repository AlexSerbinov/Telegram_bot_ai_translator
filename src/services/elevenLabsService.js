const { ElevenLabsClient } = require('@elevenlabs/elevenlabs-js');
const fs = require('fs-extra');
const { config } = require('../config/config');
const logger = require('../utils/logger');

class ElevenLabsService {
  constructor() {
    this.client = new ElevenLabsClient({
      apiKey: config.elevenLabs.apiKey,
    });

    // Mapping from ElevenLabs language codes to our internal codes
    this.languageMap = {
      'ukr': 'uk',
      'eng': 'en',
      'spa': 'es',
      'kat': 'ka',
      'ind': 'id',
      'rus': 'ru',
    };

    // Reverse mapping: our codes to ElevenLabs ISO-639-3 codes
    this.reverseLanguageMap = {
      'uk': 'ukr',
      'en': 'eng',
      'es': 'spa',
      'ka': 'kat',
      'id': 'ind',
      'ru': 'rus',
    };
  }

  /**
   * Normalize ElevenLabs language code to our internal code
   */
  normalizeLanguage(elevenLabsLangCode) {
    if (!elevenLabsLangCode) return null;
    const code = elevenLabsLangCode.toLowerCase();
    // Try direct mapping first
    if (this.languageMap[code]) return this.languageMap[code];
    // Try if it's already our internal code
    if (this.reverseLanguageMap[code]) return code;
    logger.warn(`Unknown ElevenLabs language code: ${code}`);
    return null;
  }

  /**
   * Convert speech to text using ElevenLabs Scribe V2
   */
  async speechToText(audioFilePath, language = 'auto') {
    try {
      logger.info(`[ElevenLabs] Converting speech to text (Scribe V2), language: ${language}`);

      const audioBuffer = await fs.readFile(audioFilePath);
      const audioBlob = new Blob([audioBuffer], { type: 'audio/ogg' });

      const params = {
        file: audioBlob,
        modelId: config.elevenLabs.models.stt,
        tagAudioEvents: false,
        diarize: false,
      };

      // If specific language requested, pass it as ISO-639-3
      if (language !== 'auto' && this.reverseLanguageMap[language]) {
        params.languageCode = this.reverseLanguageMap[language];
      }

      const transcription = await this.client.speechToText.convert(params);

      const detectedLang = this.normalizeLanguage(transcription.languageCode || transcription.language_code);

      const result = {
        text: transcription.text,
        detectedLanguage: detectedLang || language,
        confidence: transcription.languageProbability || transcription.language_probability || null,
      };

      logger.info(`[ElevenLabs] STT success. Detected: ${result.detectedLanguage} (confidence: ${result.confidence}), text length: ${result.text.length}`);
      return result;
    } catch (error) {
      logger.error('[ElevenLabs] Error in speech-to-text:', error);
      throw error;
    }
  }
  /**
   * Convert text to speech using ElevenLabs TTS
   */
  async textToSpeech(text, languageCode) {
    try {
      logger.info(`[ElevenLabs] TTS: "${text.substring(0, 50)}..." lang=${languageCode}`);

      const audioStream = await this.client.textToSpeech.convert(
        config.elevenLabs.ttsVoice,
        {
          text,
          modelId: config.elevenLabs.models.tts,
          languageCode: languageCode || undefined,
          outputFormat: 'mp3_44100_128',
        }
      );

      // Convert ReadableStream to Buffer
      const chunks = [];
      for await (const chunk of audioStream) {
        chunks.push(typeof chunk === 'string' ? Buffer.from(chunk) : chunk);
      }

      const buffer = Buffer.concat(chunks);
      logger.info(`[ElevenLabs] TTS success, audio size: ${buffer.length} bytes`);
      return buffer;
    } catch (error) {
      logger.error('[ElevenLabs] Error in text-to-speech:', error);
      throw error;
    }
  }

  /**
   * Generate a single-use token for ElevenLabs Realtime STT
   */
  async generateRealtimeToken() {
    try {
      logger.info('[ElevenLabs] Generating single-use realtime scribe token');
      const response = await this.client.tokens.singleUse.create('realtime_scribe');
      logger.info('[ElevenLabs] Realtime token generated successfully');
      return response.token;
    } catch (error) {
      logger.error('[ElevenLabs] Error generating realtime token:', error);
      throw error;
    }
  }
}

module.exports = new ElevenLabsService();
