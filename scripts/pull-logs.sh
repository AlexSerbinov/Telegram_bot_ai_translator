#!/usr/bin/env bash
#
# pull-logs.sh — sync server-side logs + voice-log sessions + WAV recordings
# down to the local repo so you can grep/replay everything without SSHing.
#
# Pulls into ./logs/ (gitignored):
#   logs/recordings/                       — WAV files (rsync from server)
#   logs/server-ring/{date}.json           — full /api/logs ring buffer dump
#   logs/voice-log/{sessionID}.json        — diarized transcript per session
#   logs/voice-log/_index.json             — list of all sessions known
#
# Usage:
#   ./scripts/pull-logs.sh                 — full sync
#   ./scripts/pull-logs.sh --tail          — only refresh logs + recent sessions
#   ./scripts/pull-logs.sh --device da9ed18e — filter by deviceID
#
# Cron example (every 2 minutes while you're testing):
#   */2 * * * * cd ~/Desktop/projects/ai-translator && ./scripts/pull-logs.sh --tail >/dev/null 2>&1

set -euo pipefail

# --- Config (override via env) ---
SERVER_HOST="${SERVER_HOST:-89.167.19.222}"
SERVER_USER="${SERVER_USER:-root}"
SERVER_PATH="${SERVER_PATH:-/opt/ai-translator}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
API_BASE="${API_BASE:-https://89-167-19-222.sslip.io}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$REPO_ROOT/logs"
RECORDINGS_DIR="$LOG_DIR/recordings"
RING_DIR="$LOG_DIR/server-ring"
VOICE_LOG_DIR="$LOG_DIR/voice-log"

DEVICE_FILTER=""
TAIL_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tail)    TAIL_ONLY=true; shift ;;
    --device)  DEVICE_FILTER="$2"; shift 2 ;;
    --help|-h)
      sed -n '2,/^$/p' "$0"; exit 0 ;;
    *)         echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$RECORDINGS_DIR" "$RING_DIR" "$VOICE_LOG_DIR"

DATE_STAMP="$(date +%Y-%m-%d_%H-%M)"

# --- 1. WAV recordings via rsync (fast, incremental) ---
if ! $TAIL_ONLY; then
  echo "→ Syncing WAV recordings..."
  rsync -az --stats \
    -e "ssh -i $SSH_KEY -o ConnectTimeout=8 -o BatchMode=yes" \
    "$SERVER_USER@$SERVER_HOST:$SERVER_PATH/data/recordings/" \
    "$RECORDINGS_DIR/" 2>&1 | grep -E "(Number of|Total file size|transferred)" | head -5
fi

# --- 2. Server ring buffer (/api/logs) ---
echo "→ Dumping /api/logs ring buffer..."
LOGS_URL="$API_BASE/api/logs?limit=5000"
[[ -n "$DEVICE_FILTER" ]] && LOGS_URL="${LOGS_URL}&deviceID=${DEVICE_FILTER}"
curl -sS --max-time 10 "$LOGS_URL" \
  | python3 -m json.tool > "$RING_DIR/$DATE_STAMP.json" \
  || { echo "  ! failed to fetch /api/logs"; rm -f "$RING_DIR/$DATE_STAMP.json"; }
if [[ -f "$RING_DIR/$DATE_STAMP.json" ]]; then
  count=$(python3 -c "import json; print(json.load(open('$RING_DIR/$DATE_STAMP.json')).get('count', 0))")
  echo "  saved $count entries → $RING_DIR/$DATE_STAMP.json"
fi

# --- 3. Voice log sessions ---
echo "→ Fetching voice-log session index..."
SESS_URL="$API_BASE/api/voice-log/sessions?limit=200"
[[ -n "$DEVICE_FILTER" ]] && SESS_URL="${SESS_URL}&deviceID=${DEVICE_FILTER}"
SESSIONS_JSON="$VOICE_LOG_DIR/_index.json"
if curl -sS --max-time 10 "$SESS_URL" | python3 -m json.tool > "${SESSIONS_JSON}.tmp"; then
  mv "${SESSIONS_JSON}.tmp" "$SESSIONS_JSON"
  count=$(python3 -c "import json; print(json.load(open('$SESSIONS_JSON')).get('count', 0))")
  echo "  $count sessions known"
else
  rm -f "${SESSIONS_JSON}.tmp"
  echo "  ! failed to fetch session index"
  exit 1
fi

# --- 4. Per-session diarized transcripts ---
# In --tail mode, refresh only sessions from the last hour.
echo "→ Fetching per-session transcripts..."
NOW_MS=$(($(date +%s) * 1000))
HOUR_AGO_MS=$((NOW_MS - 3600 * 1000))

python3 - <<PY
import json, os, subprocess, sys, time, urllib.parse
idx_path = "$SESSIONS_JSON"
out_dir = "$VOICE_LOG_DIR"
api_base = "$API_BASE"
tail_only = "$TAIL_ONLY" == "true"
device = "$DEVICE_FILTER"
hour_ago = $HOUR_AGO_MS

with open(idx_path) as f:
    idx = json.load(f)

fetched = 0
skipped = 0
for s in idx.get("sessions", []):
    sid = s["sessionID"]
    if tail_only and s.get("endedAt", 0) < hour_ago:
        skipped += 1
        continue
    out_file = os.path.join(out_dir, f"{sid}.json")
    url = f"{api_base}/api/voice-log/sessions/{urllib.parse.quote(sid)}"
    if device:
        url += f"?deviceID={urllib.parse.quote(device)}"
    r = subprocess.run(["curl", "-sS", "--max-time", "10", url], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        print(f"  ! {sid}: fetch failed")
        continue
    try:
        data = json.loads(r.stdout)
    except json.JSONDecodeError:
        print(f"  ! {sid}: invalid JSON")
        continue
    with open(out_file, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    fetched += 1

print(f"  fetched {fetched}, skipped {skipped}")
PY

# --- 5. Summary ---
total_wavs=$(find "$RECORDINGS_DIR" -name "*.wav" 2>/dev/null | wc -l | tr -d ' ')
total_sessions=$(find "$VOICE_LOG_DIR" -name "*.json" ! -name "_index.json" 2>/dev/null | wc -l | tr -d ' ')
total_ring_dumps=$(find "$RING_DIR" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')
echo ""
echo "Done. logs/"
echo "  recordings: $total_wavs WAVs"
echo "  voice-log:  $total_sessions sessions"
echo "  ring-dumps: $total_ring_dumps snapshots"
