#!/usr/bin/env node
/**
 * compare-transcripts.js
 *
 * Run both Gemini and Soniox transcription on a single audio file in parallel,
 * then print a side-by-side comparison, similarity score, word-level diff, and
 * (if both providers return word-level timing) a small alignment table for the
 * first 10 words.
 *
 * Usage:
 *   node scripts/compare-transcripts.js <path-to-audio>
 *
 * Diagnostic output goes to stderr. The final stdout payload is a single JSON
 * blob:
 *   {
 *     audio, gemini: {raw_text, words}, soniox: {raw_text, words},
 *     similarity_ratio, char_diff_count
 *   }
 */

const path = require('path');
const fs = require('fs');

const gemini = require('./gemini-transcribe');
const soniox = require('./soniox-transcribe');

// ---------- Levenshtein + similarity ----------

function levenshtein(a, b) {
  if (a === b) return 0;
  const al = a.length, bl = b.length;
  if (al === 0) return bl;
  if (bl === 0) return al;
  let prev = new Array(bl + 1);
  let curr = new Array(bl + 1);
  for (let j = 0; j <= bl; j++) prev[j] = j;
  for (let i = 1; i <= al; i++) {
    curr[0] = i;
    const ca = a.charCodeAt(i - 1);
    for (let j = 1; j <= bl; j++) {
      const cost = ca === b.charCodeAt(j - 1) ? 0 : 1;
      curr[j] = Math.min(
        curr[j - 1] + 1,       // insertion
        prev[j] + 1,           // deletion
        prev[j - 1] + cost,    // substitution
      );
    }
    [prev, curr] = [curr, prev];
  }
  return prev[bl];
}

function similarityRatio(a, b) {
  const maxLen = Math.max(a.length, b.length);
  if (maxLen === 0) return 1;
  const dist = levenshtein(a, b);
  return +(1 - dist / maxLen).toFixed(4);
}

// ---------- Word-level diff (LCS) ----------

function tokenize(s) {
  return (s || '').trim().split(/\s+/).filter(Boolean);
}

function wordDiff(aTokens, bTokens) {
  // LCS table
  const n = aTokens.length, m = bTokens.length;
  const dp = Array.from({ length: n + 1 }, () => new Uint32Array(m + 1));
  for (let i = 1; i <= n; i++) {
    for (let j = 1; j <= m; j++) {
      dp[i][j] = aTokens[i - 1] === bTokens[j - 1]
        ? dp[i - 1][j - 1] + 1
        : Math.max(dp[i - 1][j], dp[i][j - 1]);
    }
  }
  // Backtrack
  const ops = [];
  let i = n, j = m;
  while (i > 0 && j > 0) {
    if (aTokens[i - 1] === bTokens[j - 1]) {
      ops.push({ op: '=', a: aTokens[i - 1], b: bTokens[j - 1] });
      i--; j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      ops.push({ op: '-', a: aTokens[i - 1] });
      i--;
    } else {
      ops.push({ op: '+', b: bTokens[j - 1] });
      j--;
    }
  }
  while (i > 0) { ops.push({ op: '-', a: aTokens[i - 1] }); i--; }
  while (j > 0) { ops.push({ op: '+', b: bTokens[j - 1] }); j--; }
  ops.reverse();
  return ops;
}

function renderDiff(ops) {
  const lines = [];
  for (const o of ops) {
    if (o.op === '=') lines.push(`  ${o.a}`);
    else if (o.op === '-') lines.push(`- ${o.a}`);
    else if (o.op === '+') lines.push(`+ ${o.b}`);
  }
  return lines.join('\n');
}

// ---------- Alignment table ----------

function alignmentTable(geminiWords, sonioxWords, n = 10) {
  const rows = [];
  const len = Math.min(n, Math.max(geminiWords.length, sonioxWords.length));
  rows.push(['#', 'Gemini word', 'G start', 'G end', 'Soniox word', 'S start', 'S end']);
  for (let i = 0; i < len; i++) {
    const g = geminiWords[i] || {};
    const s = sonioxWords[i] || {};
    rows.push([
      String(i + 1),
      g.word ?? '',
      g.start != null ? g.start.toFixed(2) : '',
      g.end != null ? g.end.toFixed(2) : '',
      s.word ?? '',
      s.start != null ? s.start.toFixed(2) : '',
      s.end != null ? s.end.toFixed(2) : '',
    ]);
  }
  const widths = rows[0].map((_, ci) => Math.max(...rows.map((r) => String(r[ci]).length)));
  return rows.map((r) => r.map((c, ci) => String(c).padEnd(widths[ci])).join('  ')).join('\n');
}

// ---------- Main ----------

async function main() {
  const audioPath = process.argv[2];
  if (!audioPath) {
    console.error('Usage: node scripts/compare-transcripts.js <path-to-audio>');
    process.exit(2);
  }
  if (!fs.existsSync(audioPath)) {
    console.error(`File not found: ${audioPath}`);
    process.exit(2);
  }

  console.error(`Running Gemini + Soniox transcription on ${audioPath} ...`);
  const [geminiSettled, sonioxSettled] = await Promise.allSettled([
    gemini.transcribe(audioPath),
    soniox.transcribe(audioPath),
  ]);

  if (geminiSettled.status === 'rejected') {
    console.error('Gemini error:', geminiSettled.reason?.message || geminiSettled.reason);
  }
  if (sonioxSettled.status === 'rejected') {
    console.error('Soniox error:', sonioxSettled.reason?.message || sonioxSettled.reason);
  }

  const geminiRes = geminiSettled.status === 'fulfilled' ? geminiSettled.value : { raw_text: '', words: [] };
  const sonioxRes = sonioxSettled.status === 'fulfilled' ? sonioxSettled.value : { raw_text: '', words: [] };

  const gText = (geminiRes.raw_text || '').trim();
  const sText = (sonioxRes.raw_text || '').trim();

  const charDiff = levenshtein(gText, sText);
  const similarity = similarityRatio(gText, sText);

  // Pretty diagnostic to stderr.
  console.error('\n--- Gemini text ---');
  console.error(gText || '(empty)');
  console.error('\n--- Soniox text ---');
  console.error(sText || '(empty)');
  console.error(`\nSimilarity ratio: ${similarity}`);
  console.error(`Char edit distance: ${charDiff}`);

  console.error('\n--- Word-level diff (- gemini / + soniox) ---');
  const ops = wordDiff(tokenize(gText), tokenize(sText));
  console.error(renderDiff(ops));

  const gWords = Array.isArray(geminiRes.words) ? geminiRes.words : [];
  const sWords = Array.isArray(sonioxRes.words) ? sonioxRes.words : [];
  if (gWords.length && sWords.length) {
    console.error('\n--- First 10 words alignment ---');
    console.error(alignmentTable(gWords, sWords, 10));
  } else {
    console.error('\n(Skipping alignment table — one or both providers did not return word-level timings.)');
  }

  const out = {
    audio: path.resolve(audioPath),
    gemini: { raw_text: gText, words: gWords },
    soniox: { raw_text: sText, words: sWords },
    similarity_ratio: similarity,
    char_diff_count: charDiff,
  };
  process.stdout.write(JSON.stringify(out, null, 2) + '\n');
}

main().catch((err) => {
  console.error('Unexpected error:', err);
  process.exit(1);
});
