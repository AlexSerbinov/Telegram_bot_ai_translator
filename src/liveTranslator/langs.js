/**
 * Shared language table for the live translator engine.
 * Mirrors the list used in src/webapp/live.html and palabra.html so a single
 * source of truth covers Soniox language hints, ElevenLabs language codes,
 * and the script-mismatch filter.
 */
const LANGS = [
  { code: 'es', name: 'Spanish',    flag: '🇪🇸', script: 'latin' },
  { code: 'en', name: 'English',    flag: '🇺🇸', script: 'latin' },
  { code: 'ru', name: 'Russian',    flag: '🇷🇺', script: 'cyrillic' },
  { code: 'uk', name: 'Ukrainian',  flag: '🇺🇦', script: 'cyrillic' },
  { code: 'de', name: 'German',     flag: '🇩🇪', script: 'latin' },
  { code: 'fr', name: 'French',     flag: '🇫🇷', script: 'latin' },
  { code: 'it', name: 'Italian',    flag: '🇮🇹', script: 'latin' },
  { code: 'pt', name: 'Portuguese', flag: '🇵🇹', script: 'latin' },
  { code: 'pl', name: 'Polish',     flag: '🇵🇱', script: 'latin' },
  { code: 'tr', name: 'Turkish',    flag: '🇹🇷', script: 'latin' },
  { code: 'nl', name: 'Dutch',      flag: '🇳🇱', script: 'latin' },
  { code: 'cs', name: 'Czech',      flag: '🇨🇿', script: 'latin' },
  { code: 'ja', name: 'Japanese',   flag: '🇯🇵', script: 'other' },
  { code: 'zh', name: 'Chinese',    flag: '🇨🇳', script: 'other' },
  { code: 'ar', name: 'Arabic',     flag: '🇸🇦', script: 'other' },
];

const byCode = (code) => LANGS.find(l => l.code === code);

module.exports = { LANGS, byCode };
