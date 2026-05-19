#!/usr/bin/env node
/**
 * gemini-transcribe.js
 *
 * Transcribe an audio file via Google Gemini multimodal API with
 * word-level timestamps (start/end in seconds).
 *
 * Usage:
 *   node scripts/gemini-transcribe.js <path-to-audio>
 *
 * Supported audio: .wav .mp3 .m4a .ogg .aiff .flac
 *
 * Reads GEMINI_API_KEY from .env. Prints JSON to stdout:
 *   { language, duration_seconds, words: [{word,start,end}], raw_text }
 *
 * Note: Gemini may not always return precise per-word timing. If the model
 * falls back to sentence-level timing, each "word" entry will actually be a
 * phrase/sentence and a `granularity: "sentence"` field will be present.
 */

const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const { GoogleGenAI } = require('@google/genai');

const MIME_BY_EXT = {
  '.wav': 'audio/wav',
  '.mp3': 'audio/mp3',
  '.m4a': 'audio/mp4',
  '.mp4': 'audio/mp4',
  '.aac': 'audio/aac',
  '.ogg': 'audio/ogg',
  '.flac': 'audio/flac',
  '.aiff': 'audio/aiff',
  '.aif': 'audio/aiff',
};

async function transcribe(audioPath) {
  if (!audioPath) throw new Error('audioPath is required');
  if (!fs.existsSync(audioPath)) throw new Error(`File not found: ${audioPath}`);

  const apiKey = process.env.GEMINI_API_KEY || process.env.GOOGLE_GEMINI_API_KEY;
  if (!apiKey) throw new Error('GEMINI_API_KEY not set in .env');

  const ext = path.extname(audioPath).toLowerCase();
  const mimeType = MIME_BY_EXT[ext];
  if (!mimeType) throw new Error(`Unsupported audio extension: ${ext}`);

  const audioBytes = fs.readFileSync(audioPath);
  const audioBase64 = audioBytes.toString('base64');

  const ai = new GoogleGenAI({ apiKey });
  const model = process.env.GEMINI_TRANSCRIBE_MODEL || 'gemini-2.5-flash';

  const prompt = [
    'You are a verbatim speech transcriber. Transcribe the attached audio EXACTLY as spoken.',
    'Return ONLY a JSON object (no markdown, no code fences) with this exact shape:',
    '{',
    '  "language": "<ISO 639-1 code, e.g. uk, en, es>",',
    '  "duration_seconds": <number>,',
    '  "granularity": "word" | "sentence",',
    '  "words": [ { "word": "<token>", "start": <seconds, number>, "end": <seconds, number> } ],',
    '  "raw_text": "<full transcript as a single string>"',
    '}',
    'Rules:',
    '- Prefer per-WORD timestamps. If you truly cannot estimate per word, use sentence-level entries and set granularity to "sentence". Otherwise set granularity to "word".',
    '- Timestamps are seconds from the start of the audio (floats, 2-3 decimals).',
    '- Keep original casing, punctuation, diacritics. Do not translate.',
    '- Do not include any commentary outside the JSON.',
  ].join('\n');

  const response = await ai.models.generateContent({
    model,
    contents: [
      {
        role: 'user',
        parts: [
          { text: prompt },
          { inlineData: { mimeType, data: audioBase64 } },
        ],
      },
    ],
    config: { responseMimeType: 'application/json' },
  });

  const text = (response.text || '').trim();
  if (!text) throw new Error('Empty response from Gemini');

  // Strip accidental code fences just in case.
  const cleaned = text.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '').trim();

  let parsed;
  try {
    parsed = JSON.parse(cleaned);
  } catch (err) {
    throw new Error('Failed to parse JSON from Gemini. Raw response:\n' + text);
  }
  return parsed;
}

async function mainCli() {
  const audioPath = process.argv[2];
  if (!audioPath) {
    console.error('Usage: node scripts/gemini-transcribe.js <path-to-audio>');
    process.exit(2);
  }
  try {
    const parsed = await transcribe(audioPath);
    process.stdout.write(JSON.stringify(parsed, null, 2) + '\n');
  } catch (err) {
    console.error('Error:', err.message || err);
    process.exit(1);
  }
}

module.exports = { transcribe };

if (require.main === module) {
  mainCli();
}
