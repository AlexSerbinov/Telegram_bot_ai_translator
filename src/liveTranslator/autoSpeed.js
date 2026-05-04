/**
 * Auto-speed engine — derives target playback speed from how far behind the speaker we are.
 *
 * secondsBehind = clientReportedQueueSec + (untranslatedSrcChars / 15)
 *   (15 chars/sec is a rough Spanish/Ukrainian speaking rate)
 *
 * Mapping curve (capped at 1.55):
 *   <1s   → 1.00×
 *   1–3s  → 1.00 → 1.10
 *   3–6s  → 1.10 → 1.25
 *   6–10s → 1.25 → 1.40
 *   ≥10s  → 1.40 → 1.55 (cap)
 *
 * LERP at 15 % per tick (250 ms ⇒ ≈ 1.5 s time constant) keeps speed transitions smooth.
 */
const SPEED_MIN = 1.00;
const SPEED_MAX = 1.55;
const LERP_RATE = 0.15;
const CHARS_PER_SEC = 15;

function secondsBehind(clientQueueSec, untranslatedSrcChars) {
  return Math.max(0, clientQueueSec) + Math.max(0, untranslatedSrcChars) / CHARS_PER_SEC;
}

function targetSpeedFor(sb) {
  if (sb < 1)  return 1.00;
  if (sb < 3)  return 1.00 + (sb - 1)  * 0.05;          // 1.00 → 1.10
  if (sb < 6)  return 1.10 + (sb - 3)  * 0.05;          // 1.10 → 1.25
  if (sb < 10) return 1.25 + (sb - 6)  * 0.0375;        // 1.25 → 1.40
  return Math.min(SPEED_MAX, 1.40 + (sb - 10) * 0.03);
}

function lerp(currentSpeed, targetSpeed, dampening = LERP_RATE) {
  return currentSpeed * (1 - dampening) + targetSpeed * dampening;
}

function clamp(v) { return Math.max(SPEED_MIN, Math.min(SPEED_MAX, v)); }

module.exports = { secondsBehind, targetSpeedFor, lerp, clamp, SPEED_MIN, SPEED_MAX };
