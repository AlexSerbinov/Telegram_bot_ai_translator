/**
 * Groq gpt-oss-120b incremental streaming translator.
 *
 * Sends ONLY the new source segment plus a short rolling context. The model is
 * instructed to translate the new segment as a continuation of the prior context
 * and never repeat it. Responses are validated by two anti-hallucination guards:
 *   (1) echo guard — drop if response starts with or contains the recent context tail
 *   (2) length guard — drop if response is wildly longer than the new source
 *
 * Ported from /api/translate-fast logic in src/server.js.
 */
const { byCode } = require('./langs');

const ENDPOINT = 'https://api.groq.com/openai/v1/chat/completions';
const MODEL = 'openai/gpt-oss-120b';

function buildSystemPrompt(fromName, toName, contextSrc, contextTrans) {
  if (contextSrc && contextTrans) {
    return `You are a real-time streaming translator from ${fromName} into ${toName}.
Previously spoken context (already delivered to the listener — DO NOT re-translate or repeat any of it):
  Source:      "${contextSrc}"
  Translation: "${contextTrans}"

Translate ONLY the NEW source segment provided by the user, as a natural continuation that flows from the previous context. Match the previous translation's tense, gender and tone. Output ONLY the translation of the new segment — no echoes of prior context, no labels, no quotes, no explanations.`;
  }
  return `You are a translation engine from ${fromName} into ${toName}. Translate the user text. Output only the translation, no quotes, no explanations.`;
}

/**
 * @param {Object}   args
 * @param {string}   args.apiKey                 Groq API key
 * @param {string}   args.text                   new source segment to translate
 * @param {string}   args.sourceLang             ISO code (e.g. 'es')
 * @param {string}   args.targetLang             ISO code (e.g. 'uk')
 * @param {string}   [args.contextSrc='']        recent already-translated source tail
 * @param {string}   [args.contextTrans='']      recent already-spoken translation tail
 * @returns {Promise<{ translation: string, elapsedMs: number, dropReason?: string }>}
 */
async function translateIncremental({ apiKey, text, sourceLang, targetLang, contextSrc = '', contextTrans = '' }) {
  if (!text) throw new Error('translator: missing text');
  const fromLang = byCode(sourceLang);
  const toLang   = byCode(targetLang);
  if (!fromLang || !toLang) throw new Error(`translator: unsupported pair ${sourceLang}→${targetLang}`);

  const systemPrompt = buildSystemPrompt(fromLang.name, toLang.name, contextSrc, contextTrans);

  const t0 = Date.now();
  const response = await fetch(ENDPOINT, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: MODEL,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user',   content: text },
      ],
      temperature: 0.2,
    }),
  });
  if (!response.ok) {
    const err = await response.text();
    throw new Error(`Groq ${response.status}: ${err}`);
  }
  const data = await response.json();
  const raw = (data?.choices?.[0]?.message?.content || '').trim();
  const elapsedMs = Date.now() - t0;
  if (!raw) return { translation: '', elapsedMs, dropReason: 'empty' };

  // Guard (1): echo of recent context tail
  const tailProbe = (contextTrans || '').trim().slice(-60);
  if (tailProbe && (raw.startsWith(tailProbe) || raw.includes(tailProbe))) {
    return { translation: raw, elapsedMs, dropReason: 'echoes-context' };
  }
  // Guard (2): wildly long output
  if (raw.length > text.length * 4 + 80) {
    return { translation: raw, elapsedMs, dropReason: 'too-long' };
  }

  return { translation: raw, elapsedMs };
}

module.exports = { translateIncremental, MODEL };
