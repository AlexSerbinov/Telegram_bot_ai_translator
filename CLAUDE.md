# AI Translator — Cloud & Deployment

## Architecture

```
Telegram User
    │
    ├── Bot commands (/start, /voice, /settings...)
    │       → Telegraf (long polling)
    │       → Gemini (translation) + ElevenLabs (STT/TTS)
    │
    └── Mini App (voice translator)
            → Express server (/webapp/index.html)
            → API: /api/token, /api/translate, /api/tts
            → Real-time STT: Soniox or ElevenLabs WebSocket
```

**Stack:** Node.js 18+, Express 5, Telegraf, MongoDB 7, Mongoose

**Key services:**
- **Gemini** — translation + language detection
- **ElevenLabs** — speech-to-text (Scribe V2) + text-to-speech
- **Soniox** — real-time STT in Mini App (via WebSocket)

---

## Two Environments

| | DEV (local) | PROD (Hetzner) |
|---|---|---|
| **Bot token** | `8235716559:...` (dev bot) | `7916554697:...` (prod bot) |
| **WEBAPP_URL** | ngrok HTTPS tunnel | `https://89-167-19-222.sslip.io` |
| **NODE_ENV** | `development` | `production` |
| **MongoDB** | localhost:27017 (Docker) | localhost:27017 (Docker) |
| **Process** | nodemon | PM2 |
| **HTTPS** | ngrok | Caddy reverse proxy |

**Important:** DEV and PROD are separate Telegram bots. They don't interfere with each other.

---

## PROD Server (Hetzner)

- **IP:** 89.167.19.222
- **SSH:** `ssh -i ~/.ssh/id_rsa root@89.167.19.222`
- **OS:** Ubuntu, 8GB RAM, 75GB SSD, Helsinki datacenter
- **Project path:** `/opt/ai-translator`
- **Process manager:** PM2 (`pm2 status`, `pm2 logs ai-translator`)
- **HTTPS:** Caddy (systemd service, auto-SSL via ZeroSSL)
- **Database:** MongoDB 7 in Docker (`mongo-translator` container, port 27017)
- **Domain:** `https://89-167-19-222.sslip.io` (sslip.io resolves to server IP)

### Caddy config (`/etc/caddy/Caddyfile`)
```
{
    email admin@translator.app
    acme_ca https://acme.zerossl.com/v2/DV90
}

89-167-19-222.sslip.io {
    reverse_proxy localhost:3001
}
```

### PM2
```bash
pm2 status                    # check status
pm2 logs ai-translator        # view logs
pm2 restart ai-translator     # restart
pm2 stop ai-translator        # stop
```

### Server .env
Located at `/opt/ai-translator/.env` — NOT tracked in git. Contains PROD bot token and `WEBAPP_URL=https://89-167-19-222.sslip.io`.

---

## CI/CD

**Trigger:** Push to `main` branch
**Workflow:** `.github/workflows/deploy.yml`

```
Push to main → GitHub Actions → SSH to server → git reset --hard → npm install → pm2 restart
```

**GitHub Secrets:**
- `DEPLOY_SSH_KEY` — SSH private key for server access
- `DEPLOY_HOST` — `89.167.19.222`

### Deploy flow
1. Work on `dev` branch
2. When ready, merge `dev` → `main` and push
3. GitHub Actions auto-deploys to server (~10 seconds)
4. PM2 restarts the bot with new code

---

## Local Development

### Prerequisites
- Node.js 18+
- MongoDB running locally (via Docker: `docker run -d --name mongo-translator -p 27017:27017 -e MONGO_INITDB_ROOT_USERNAME=admin -e MONGO_INITDB_ROOT_PASSWORD=secretpassword mongo:7`)
- ngrok installed (`brew install ngrok`) and authenticated (`ngrok config add-authtoken <token>`)

### Quick start

```bash
# 1. Install dependencies
npm install

# 2. Copy and configure .env
cp env.example .env
# Edit .env with your API keys (DEV bot token is already in env.example comments)

# 3. Start with ngrok (recommended for Mini App testing)
npm run dev:ngrok

# 4. Or start without ngrok (bot only, no Mini App HTTPS)
npm run dev
```

### `npm run dev:ngrok` does:
1. Starts ngrok tunnel to port 3001
2. Gets the HTTPS URL from ngrok
3. Updates `WEBAPP_URL` in `.env` with ngrok URL
4. Starts the bot with nodemon (auto-restart on file changes)
5. On exit, restores `WEBAPP_URL` to `http://localhost:3001`

### Without ngrok
- `npm run dev` — starts bot with nodemon, Mini App available at `http://localhost:3001/webapp/index.html` but **no HTTPS** (microphone won't work in Telegram Mini App)
- `npm start` — starts bot without auto-restart

---

## Project Structure

```
src/
├── bot.js                  # Entry point — starts Telegraf bot + Express server
├── server.js               # Express routes: /webapp, /api/*
├── config/config.js        # All env var reading + defaults
├── handlers/
│   ├── commandHandlers.js  # /start, /settings, /voice, /stats, etc.
│   ├── callbackHandlers.js # Inline keyboard callbacks
│   └── audioHandler.js     # Voice message → STT → translate → TTS
├── models/User.js          # Mongoose schema
├── services/
│   ├── databaseService.js  # MongoDB operations
│   ├── elevenLabsService.js# STT (Scribe V2) + TTS + realtime token
│   ├── geminiService.js    # Translation + language detection
│   ├── openaiService.js    # Orchestrator: delegates to ElevenLabs + Gemini
│   └── languageService.js  # Language metadata + keyboard generation
├── utils/logger.js         # Console logger
└── webapp/index.html       # Telegram Mini App (single HTML file)
```

---

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | Yes | Telegram bot token (DEV or PROD) |
| `OPENAI_API_KEY` | Yes | OpenAI key (required by validator) |
| `ELEVEN_LABS_API_KEY` | No | ElevenLabs STT/TTS |
| `GOOGLE_GEMINI_API_KEY` | No | Gemini translation |
| `SONIOX_API_KEY` | No | Soniox real-time STT |
| `STT_PROVIDER` | No | `soniox` or `elevenlabs` (default: `soniox`) |
| `MONGODB_URI` | No | MongoDB connection string |
| `SERVER_PORT` | No | Express port (default: `3000`) |
| `WEBAPP_URL` | No | Public HTTPS URL for Mini App |
| `NODE_ENV` | No | `development` or `production` |
| `LOG_LEVEL` | No | `info`, `debug`, `warn`, `error` |

---

## Troubleshooting

### Bot not responding
```bash
# On server
ssh -i ~/.ssh/id_rsa root@89.167.19.222 "pm2 logs ai-translator --lines 50"
```

### Mini App not loading
- Check WEBAPP_URL is correct HTTPS URL
- Check Caddy is running: `systemctl status caddy`
- Check Express is listening: `curl http://localhost:3001/webapp/index.html`

### MongoDB connection issues
```bash
# Check container
docker ps | grep mongo
# Restart if needed
docker restart mongo-translator
```

### CI/CD not deploying
- Check GitHub Actions tab in the repo
- Verify secrets: `gh secret list --repo AlexSerbinov/Telegram_bot_ai_translator`
- SSH manually: `ssh -i ~/.ssh/id_rsa root@89.167.19.222 "cd /opt/ai-translator && git log --oneline -1"`
