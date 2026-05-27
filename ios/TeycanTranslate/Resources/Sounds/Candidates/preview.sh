#!/usr/bin/env bash
# Audition all 8 candidate earcon pairs for Relay's start/end-of-speech cues.
# Plays each pair as "Start … 0.8s pause … End … 1.2s pause", waits for Enter
# between pairs so you can decide without time pressure.

set -e
cd "$(dirname "$0")"

PAIRS=(
  "01_TinkPair        Tink → Pop                 (classic UI, crisp)"
  "02_PopPair         Glass → Bottle             (rising chime → falling chime, natural pair)"
  "03_GlassPair       Ping → Tink                (bell → click)"
  "04_HeroPair        Hero → Submarine           (orchestral, dramatic)"
  "05_BottlePair      Bottle → Frog              (mid-pitched, organic)"
  "06_PingPair        880Hz → 660Hz sine         (Google Translate-like, pure tones)"
  "07_SiriStyle       Ascending 2-tone → Descending 2-tone (Siri start/stop vibe)"
  "08_DeepLWhoosh     Filtered noise whoosh up/down       (DeepL-like, soft)"
)

for pair in "${PAIRS[@]}"; do
  dir="${pair%% *}"
  label="${pair#"$dir"}"
  label="${label## }"
  echo
  echo "▶ $dir  —  $label"

  # Prefer .wav when present (the synthesized pairs), fall back to .aiff (macOS sounds).
  if [[ -f "$dir/start.wav" ]]; then start="$dir/start.wav"; else start="$dir/start.aiff"; fi
  if [[ -f "$dir/end.wav"   ]]; then end="$dir/end.wav";     else end="$dir/end.aiff";   fi

  echo "  start …"
  afplay -v 1.0 "$start"
  sleep 0.8
  echo "  end …"
  afplay -v 1.0 "$end"
  sleep 0.4

  read -r -p "  → Press Enter for next pair (or Ctrl+C to stop) " _
done

echo
echo "Done. Tell Claude which pair you liked (e.g., '07' or 'Siri') and it'll wire it in."
