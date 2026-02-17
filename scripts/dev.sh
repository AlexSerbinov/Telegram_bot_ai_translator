#!/bin/bash
# Local development script with ngrok HTTPS tunnel
# Usage: ./scripts/dev.sh

set -e

PORT=${SERVER_PORT:-3001}
ENV_FILE=".env"

# Check ngrok is installed
if ! command -v ngrok &> /dev/null; then
  echo "Error: ngrok is not installed. Install it: brew install ngrok"
  exit 1
fi

# Kill any existing ngrok processes
pkill -f "ngrok http" 2>/dev/null || true
sleep 1

# Start ngrok in background
echo "Starting ngrok on port $PORT..."
ngrok http $PORT --log=stdout > /tmp/ngrok.log 2>&1 &
NGROK_PID=$!

# Wait for ngrok to start and get the URL
echo "Waiting for ngrok tunnel..."
NGROK_URL=""
for i in {1..15}; do
  NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -o '"public_url":"https://[^"]*"' | head -1 | cut -d'"' -f4)
  if [ -n "$NGROK_URL" ]; then
    break
  fi
  sleep 1
done

if [ -z "$NGROK_URL" ]; then
  echo "Error: Failed to get ngrok URL. Check ngrok auth: ngrok config add-authtoken <token>"
  kill $NGROK_PID 2>/dev/null
  exit 1
fi

echo ""
echo "======================================"
echo "  ngrok URL: $NGROK_URL"
echo "  Mini App:  $NGROK_URL/webapp/index.html"
echo "======================================"
echo ""

# Update WEBAPP_URL in .env
if grep -q "^WEBAPP_URL=" "$ENV_FILE"; then
  sed -i.bak "s|^WEBAPP_URL=.*|WEBAPP_URL=$NGROK_URL|" "$ENV_FILE"
  rm -f "$ENV_FILE.bak"
else
  echo "WEBAPP_URL=$NGROK_URL" >> "$ENV_FILE"
fi

# Cleanup on exit
cleanup() {
  echo ""
  echo "Stopping ngrok..."
  kill $NGROK_PID 2>/dev/null
  # Restore localhost URL
  sed -i.bak "s|^WEBAPP_URL=.*|WEBAPP_URL=http://localhost:$PORT|" "$ENV_FILE"
  rm -f "$ENV_FILE.bak"
  echo "Done."
}
trap cleanup EXIT INT TERM

# Start the bot with nodemon
echo "Starting bot with nodemon..."
npx nodemon src/bot.js
