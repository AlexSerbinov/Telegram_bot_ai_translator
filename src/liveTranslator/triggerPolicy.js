/**
 * Adaptive trigger policy — decides when to fire a translate request based on
 * pending source size and current TTS audio queue depth.
 *
 * Three modes (matches client live.html behavior):
 *   queue < 0.5s       → 'catch-up'   — fire small chunks aggressively (any punct or 25+ chars)
 *   0.5s ≤ queue < 1.5 → 'balanced'   — fire on .!?, on weak punct only if 40+ chars, on growth 80+
 *   queue ≥ 1.5s       → 'caught-up'  — patient: only .!? or 120+ chars
 * Hard ceiling: pending ≥ 200 chars always fires.
 */
const STRONG_PUNCT_RE = /[.!?…]\s*$/;
const WEAK_PUNCT_RE   = /[,;:]\s*$/;

/**
 * @param {string} pending  trimmed source text not yet sent for translation
 * @param {number} queueSec seconds of synthesized audio queued ahead of the playhead
 * @returns {{ fire: boolean, mode: 'catch-up'|'balanced'|'caught-up' }}
 */
function decide(pending, queueSec) {
  if (!pending) return { fire: false, mode: 'idle' };
  const tail4 = pending.slice(-4);
  const hasStrong = STRONG_PUNCT_RE.test(tail4);
  const hasWeak   = WEAK_PUNCT_RE.test(tail4);

  let mode, fire = false;
  if (queueSec < 0.5) {
    mode = 'catch-up';
    fire = hasStrong || hasWeak || pending.length >= 25;
  } else if (queueSec < 1.5) {
    mode = 'balanced';
    fire = hasStrong || (hasWeak && pending.length >= 40) || pending.length >= 80;
  } else {
    mode = 'caught-up';
    fire = hasStrong || pending.length >= 120;
  }
  if (pending.length >= 200) fire = true;
  return { fire, mode };
}

module.exports = { decide, STRONG_PUNCT_RE, WEAK_PUNCT_RE };
