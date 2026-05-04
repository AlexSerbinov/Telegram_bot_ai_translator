/**
 * Word-level script filter — drops Soniox tokens whose script doesn't match the source language.
 * Soniox occasionally slips other-language words through `language_hints`; this prevents them
 * from polluting the accumulated source we hand off to the translator.
 *
 * Ported verbatim from src/webapp/live.html `filterToScript()`.
 */
const { byCode } = require('./langs');

const CYRILLIC_RE = /[Ѐ-ӿ]/;
const LATIN_RE = /[A-Za-zÀ-ÿ]/;

/**
 * @param {string} text
 * @param {string} sourceLangCode  e.g. 'es', 'ru', 'ja'
 * @returns {string}  text with off-script words removed (whitespace preserved)
 */
function filterToScript(text, sourceLangCode) {
  if (!text) return text;
  const src = byCode(sourceLangCode);
  if (!src || src.script === 'other') return text; // CJK / Arabic — guard disabled
  return text.split(/(\s+)/).filter(tok => {
    if (!tok || /^\s+$/.test(tok)) return true;
    if (src.script === 'latin')    return !CYRILLIC_RE.test(tok);
    if (src.script === 'cyrillic') return CYRILLIC_RE.test(tok) || !LATIN_RE.test(tok);
    return true;
  }).join('');
}

module.exports = { filterToScript, CYRILLIC_RE, LATIN_RE };
