# AI Translator — Cloud & Deployment

## Communication language (with the user, in chat)

**Always reply to the user in Ukrainian in this project.** This is a project-level
override of the user's global English-default working language. All chat
explanations, status updates, questions, and end-of-turn summaries go in
Ukrainian. `SHORT_OUTPUT` and `WATCH` also in Ukrainian (existing rules apply).

What stays English (do NOT translate):
- Code, comments, commit messages, PR descriptions, git branch names
- File paths, code identifiers, CLI commands, model IDs (`gpt-realtime`,
  `Endpoints.OpenAI.calls`, `/api/voice-log`, etc.)
- DESIGN.md, technical docs already in English
- This CLAUDE.md and other repo docs

Do NOT auto-nudge the user toward English in this project. The global
"soft nudge" rule from `~/.claude/CLAUDE.md` is overridden here.

## Cross-stack tasks (iOS ↔ backend)

Many tasks in this project touch **both** the SwiftUI iOS app and the
Express backend. The iOS app is the *client* — it ships UI changes and
wiring; the backend is what those wires connect to. A request that looks
like "add an iOS setting" almost always means there's a corresponding API
contract to update on the server.

**Default expectation when you pick up any task here:**

1. **Audit both sides before coding.** Read the relevant iOS files
   (`ios/TeycanTranslate/Sources/...`) *and* the backend handler
   (`src/server.js`, `src/services/*`). Decide whether the change is
   iOS-only, backend-only, or both — and say so to the user before
   starting.
2. **If both sides are affected, implement both in the same session.**
   Don't ship a half-task where the iOS UI selects an option the backend
   silently ignores (this happened once — Phrase TTS provider selector
   was iOS-only at first, so picking "Soniox" kept playing ElevenLabs).
3. **Redeploy the backend when its code changed.** The iOS app on a
   physical iPhone defaults to the production backend at
   `https://89-167-19-222.sslip.io` (see `Endpoints.swift`), so backend
   work without deploy = no observable change. Either ask the user to
   merge to `main` (CI auto-deploys), or `gh workflow run` after the
   merge. Don't tell the user "done" until the new endpoint is live
   *and* you've smoke-tested it (e.g. `curl` the endpoint, check the
   response type).
4. **iOS-only tasks redeploy via `xcrun devicectl`** — no backend touch.
   Backend-only tasks don't need an iOS rebuild.

This rule applies to *all* future work in this repo. When you spot a
task that could be misclassified (user says "iOS thing" but the API
contract has to change too), call it out up front instead of assuming.

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

Standalone demo pages (do not affect main flow):
    /webapp/live.html      — Soniox → Groq → ElevenLabs streaming pipeline
    /webapp/palabra.html   — Palabra.ai speech-to-speech
    /webapp/realtime.html  — OpenAI gpt-realtime-translate (WebRTC, mic → translated audio + captions)
```

**Stack:** Node.js 18+, Express 5, Telegraf, MongoDB 7, Mongoose

**Key services:**
- **Gemini** — translation + language detection (default provider)
- **Groq** — alternative translation provider (OpenAI-compatible, LPU inference)
- **ElevenLabs** — speech-to-text (Scribe V2) + text-to-speech
- **Soniox** — real-time STT in Mini App (via WebSocket)
- **OpenAI Realtime Translation** — `gpt-realtime-translate` model on `/webapp/realtime.html`. Browser ↔ OpenAI WebRTC; server only mints a short-lived `client_secret` via `POST /api/realtime/session`. Audio never passes through our server. Supported target languages: `es, pt, fr, ja, ru, zh, de, ko, hi, id, vi, it, en` (no Ukrainian output yet).

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
Located at `/opt/ai-translator/.env` — synced automatically from GitHub Secret `PROD_ENV_FILE` on each deploy. See "Env Sync" section below.

---

## CI/CD

**Trigger:** Push to `main` branch
**Workflow:** `.github/workflows/deploy.yml`

```
Push to main → GitHub Actions → SSH to server → sync .env → git reset --hard → npm install → pm2 restart
```

**GitHub Secrets:**
- `DEPLOY_SSH_KEY` — SSH private key for server access
- `DEPLOY_HOST` — `89.167.19.222`
- `PROD_ENV_FILE` — full production `.env` content (synced via `npm run env:push`)

### Deploy flow
1. Work on `dev` branch
2. When ready, merge `dev` → `main` and push
3. GitHub Actions auto-deploys to server (~10 seconds)
4. `.env` is synced from `PROD_ENV_FILE` secret before restart
5. PM2 restarts the bot with new code

### Env Sync (`.env` → production)

Production `.env` is managed via GitHub Secret, not manually on the server.

**How it works:**
```
.env (local, dev values)
  + .env.production.overrides (prod bot token, URL, NODE_ENV)
  = GitHub Secret PROD_ENV_FILE
  → deploy workflow writes to /opt/ai-translator/.env
```

**Files:**
- `.env.production.overrides` — prod-specific values that differ from local (gitignored)
- `env.production.overrides.example` — template for the overrides file
- `scripts/sync-env.sh` — script that merges `.env` + overrides and pushes to GitHub Secret

**Usage:**
```bash
# One-time setup
cp env.production.overrides.example .env.production.overrides
# Edit with prod bot token (WEBAPP_URL and NODE_ENV are pre-filled)

# When you add/change keys in .env
npm run env:push
# Shows keys, asks confirmation, pushes to GitHub Secret
# Next deploy will use the updated .env
```

**Prod overrides** (values that differ from dev):
- `TELEGRAM_BOT_TOKEN` — prod bot token (`7916554697:...`)
- `WEBAPP_URL` — `https://89-167-19-222.sslip.io`
- `NODE_ENV` — `production`

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
│   ├── geminiService.js    # Translation + language detection (default)
│   ├── groqService.js      # Translation via Groq LPU (OpenAI-compatible)
│   ├── openaiService.js    # Orchestrator: delegates to active provider + ElevenLabs
│   └── languageService.js  # Language metadata + keyboard generation
├── utils/logger.js         # Console logger
└── webapp/index.html       # Telegram Mini App (single HTML file)
```

---

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | Yes | Telegram bot token (DEV or PROD) |
| `OPENAI_API_KEY` | Yes | OpenAI key (required by validator; also powers `/webapp/realtime.html`) |
| `OPENAI_REALTIME_MODEL` | No | Default `gpt-realtime-translate` |
| `OPENAI_REALTIME_TRANSCRIPTION_MODEL` | No | Default `gpt-realtime-whisper` |
| `ELEVEN_LABS_API_KEY` | No | ElevenLabs STT/TTS |
| `GOOGLE_GEMINI_API_KEY` | No | Gemini translation |
| `GROQ_API_KEY` | No | Groq LPU translation (when `TRANSLATION_PROVIDER=groq`) |
| `TRANSLATION_PROVIDER` | No | `gemini` (default) or `groq` |
| `TRANSLATION_MODEL` | No | Model for Groq (default: `openai/gpt-oss-120b`) |
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

---

## Design System

**ALWAYS read `DESIGN.md` (in repo root) before making any visual or UI decision.**

All font choices, colors, spacing, motion, tab naming, and layout structures are defined there. Do not deviate without explicit user approval. In QA mode, flag any code that does not match `DESIGN.md`.

Key locks (full spec in `DESIGN.md`):
- **Aesthetic:** Editorial-Strict (sharp, restrained, sans-only, no warm decoration)
- **Accent color:** Forest Green `#1F4A3A` (light) / `#3D8A6A` (dark). Replaced earlier amber.
- **Typography:** SF Pro Display Bold tight (-0.03em) for headers, SF Pro Text for body, JetBrains Mono for data/eyebrow.
- **Tab names:** Phrase (Voice) / Companion (Realtime) / Bridge (Chat). Use these names in code, copy, App Store, marketing.
- **Mode-specific layouts:** Each tab has unique structure. Phrase = lang pair + output card + square mic. Companion = AirPods status + transcript stream + square mic + headphones gate. Bridge = lang pair + symmetric two-side stage + model node + round mic.
- **Brand:** wordmark only on icon. Dog Teycan lives in onboarding screen 2, About, paw-print easter eggs.

When porting to SwiftUI, write tokens to:
- `ios/TeycanTranslate/Sources/DesignSystem/Colors.swift` — color tokens with light/dark variants
- `ios/TeycanTranslate/Sources/DesignSystem/Typography.swift` — font roles + scale
- `ios/TeycanTranslate/Sources/DesignSystem/Spacing.swift` — spacing scale + radius scale (create new file)
- `ios/TeycanTranslate/Sources/DesignSystem/Motion.swift` — animation specs (create new file)

## Skill routing

When the user's request matches an available skill, ALWAYS invoke it using the Skill tool as your FIRST action. Do NOT answer directly, do NOT use other tools first. The skill has specialized workflows that produce better results than ad-hoc answers.

Key routing rules:
- Product ideas, "is this worth building", brainstorming → invoke `office-hours`
- Bugs, errors, "why is this broken", 500 errors → invoke `investigate`
- Ship, deploy, push, create PR → invoke `ship`
- QA, test the site, find bugs → invoke `qa`
- Code review, check my diff → invoke `review`
- Update docs after shipping → invoke `document-release`
- Weekly retro → invoke `retro`
- Design system, brand, visual decisions → invoke `design-consultation`
- Visual audit, design polish → invoke `design-review`
- Architecture review → invoke `plan-eng-review`
- Save progress, checkpoint, resume → invoke `checkpoint`
- Code quality, health check → invoke `health`
