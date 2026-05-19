#!/usr/bin/env node
/**
 * soniox-transcribe.js
 *
 * Async (non-realtime) Soniox transcription via the REST API.
 *
 * Flow:
 *   POST /v1/files                          (multipart upload local audio)
 *   POST /v1/transcriptions                 (model: stt-async-v4, file_id)
 *   GET  /v1/transcriptions/{id}            (poll until status=completed)
 *   GET  /v1/transcriptions/{id}/transcript (final tokens with start_ms/end_ms)
 *   DELETE both file and transcription afterwards (cleanup)
 *
 * Usage:
 *   node scripts/soniox-transcribe.js <path-to-audio>
 *
 * Reads SONIOX_API_KEY from .env. Prints JSON to stdout:
 *   { language, raw_text, words: [{word,start,end}] }
 *
 * Also exports `transcribe(path) -> Promise<{language, raw_text, words}>`
 * for use by compare-transcripts.js.
 */

const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const API_BASE = 'https://api.soniox.com';
const MODEL = process.env.SONIOX_ASYNC_MODEL || 'stt-async-v4';
const POLL_INTERVAL_MS = 1500;
const MAX_WAIT_MS = 60_000;

function getApiKey() {
  const key = process.env.SONIOX_API_KEY;
  if (!key) throw new Error('SONIOX_API_KEY not set in .env');
  return key;
}

async function apiFetch(endpoint, { method = 'GET', body, headers = {} } = {}) {
  const apiKey = getApiKey();
  const res = await fetch(`${API_BASE}${endpoint}`, {
    method,
    headers: { Authorization: `Bearer ${apiKey}`, ...headers },
    body,
  });
  if (!res.ok) {
    const msg = await res.text();
    throw new Error(`Soniox HTTP ${res.status} ${res.statusText} @ ${method} ${endpoint}: ${msg}`);
  }
  if (method === 'DELETE') return null;
  return res.json();
}

async function uploadFile(audioPath) {
  const form = new FormData();
  const buf = fs.readFileSync(audioPath);
  form.append('file', new Blob([buf]), path.basename(audioPath));
  const res = await apiFetch('/v1/files', { method: 'POST', body: form });
  return res.id;
}

async function createTranscription(fileId, languageHints) {
  const config = {
    model: MODEL,
    file_id: fileId,
    enable_language_identification: true,
  };
  if (languageHints && languageHints.length) config.language_hints = languageHints;
  const res = await apiFetch('/v1/transcriptions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(config),
  });
  return res.id;
}

async function waitUntilCompleted(transcriptionId) {
  const start = Date.now();
  while (true) {
    const res = await apiFetch(`/v1/transcriptions/${transcriptionId}`);
    if (res.status === 'completed') return res;
    if (res.status === 'error') {
      throw new Error(`Soniox transcription error: ${res.error_message || 'unknown'}`);
    }
    if (Date.now() - start > MAX_WAIT_MS) {
      throw new Error(`Timed out after ${MAX_WAIT_MS}ms waiting for transcription`);
    }
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
  }
}

async function fetchTranscript(transcriptionId) {
  return apiFetch(`/v1/transcriptions/${transcriptionId}/transcript`);
}

async function safeDelete(endpoint) {
  try { await apiFetch(endpoint, { method: 'DELETE' }); } catch (_) { /* ignore */ }
}

function tokensToWords(tokens) {
  if (!Array.isArray(tokens)) return [];
  // Soniox tokens are sub-word pieces; group by whitespace boundaries to make "words".
  const words = [];
  let cur = null;
  for (const t of tokens) {
    if (!t || typeof t.text !== 'string') continue;
    if (t.translation_status === 'translation') continue; // skip translation tokens
    const txt = t.text;
    const startsNew = /^\s/.test(txt) || cur === null;
    const cleaned = txt.replace(/^\s+/, '');
    if (startsNew) {
      if (cur && cur.word.length) words.push(cur);
      cur = {
        word: cleaned,
        start: typeof t.start_ms === 'number' ? +(t.start_ms / 1000).toFixed(3) : null,
        end: typeof t.end_ms === 'number' ? +(t.end_ms / 1000).toFixed(3) : null,
      };
    } else {
      cur.word += cleaned;
      if (typeof t.end_ms === 'number') cur.end = +(t.end_ms / 1000).toFixed(3);
    }
  }
  if (cur && cur.word.length) words.push(cur);
  return words.filter((w) => w.word.trim().length > 0);
}

function tokensLanguage(tokens) {
  if (!Array.isArray(tokens)) return null;
  for (const t of tokens) {
    if (t && typeof t.language === 'string') return t.language;
  }
  return null;
}

async function transcribe(audioPath, opts = {}) {
  if (!fs.existsSync(audioPath)) throw new Error(`File not found: ${audioPath}`);

  const languageHints = opts.languageHints || ['uk', 'en'];
  let fileId = null;
  let transcriptionId = null;
  try {
    fileId = await uploadFile(audioPath);
    transcriptionId = await createTranscription(fileId, languageHints);
    await waitUntilCompleted(transcriptionId);
    const result = await fetchTranscript(transcriptionId);

    const tokens = result.tokens || [];
    const words = tokensToWords(tokens);
    const language = tokensLanguage(tokens);
    const raw_text = (result.text != null)
      ? String(result.text)
      : words.map((w) => w.word).join(' ').replace(/\s+([.,!?;:])/g, '$1').trim();

    const out = { language, raw_text };
    if (words.length) out.words = words;
    return out;
  } finally {
    if (transcriptionId) await safeDelete(`/v1/transcriptions/${transcriptionId}`);
    if (fileId) await safeDelete(`/v1/files/${fileId}`);
  }
}

async function mainCli() {
  const audioPath = process.argv[2];
  if (!audioPath) {
    console.error('Usage: node scripts/soniox-transcribe.js <path-to-audio>');
    process.exit(2);
  }
  try {
    const out = await transcribe(audioPath);
    process.stdout.write(JSON.stringify(out, null, 2) + '\n');
  } catch (err) {
    console.error('Error:', err.message || err);
    process.exit(1);
  }
}

module.exports = { transcribe };

if (require.main === module) {
  mainCli();
}
