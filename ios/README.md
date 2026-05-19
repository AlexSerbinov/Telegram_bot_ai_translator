# Teycan Translate — iOS App

Native SwiftUI live voice translator with three modes: **Phrase**, **Companion**, **Bridge**.

Backend: shared Express server at `https://89-167-19-222.sslip.io` (or local `http://localhost:3001` for dev).

## Status — v1.0 stable

| Mode | What it does | Pipeline |
|---|---|---|
| **Phrase** | One-shot dictation → translation → speak | Soniox streaming STT → Groq translation → ElevenLabs TTS |
| **Companion** | Continuous one-way live translation (headphones required) | `gpt-realtime-translate` over WebRTC |
| **Bridge** | Two-way conversational translator (mediator) | `gpt-realtime` over WebRTC + Soniox parallel STT for streaming user transcript |

**Tests:** `xcodebuild test` — **129 tests, 0 failures**.

---

## What's in this build

### Audio + transcription
- AVAudioEngine PCM capture, downsampled to 16 kHz mono Int16 with a streaming `AVAudioConverter` (no more zero-frame outputs).
- Soniox real-time STT (`stt-rt-v4`) over WebSocket for low-latency streaming user transcripts on Bridge.
- gpt-4o-transcribe via OpenAI Realtime API as the fallback when Soniox starves.
- WebRTC `voiceChat` mode for echo cancellation.
- Mic forced to built-in iPhone microphone; speaker forced to loudspeaker by default (unless headphones/AirPods are connected).
- Per-session WAV capture (16-bit/16 kHz/mono) auto-uploaded to the backend on session stop for offline analysis.

### Translation behavior
- **DefaultPrompt v9** — strict translator preamble, "ABSOLUTE RULES" block forbidding greetings / introductions / "Sure" / "How can I help" / similar conversational openers, plus an explicit "never speak first" rule.
- Fully parametric prompt by `langA` / `langB` — no hardcoded "Ukrainian" / "Spanish" strings anywhere.
- Third-language fallback: input in a third language is translated to side B by default.
- VAD: OpenAI `semantic_vad` with `eagerness: low` — LLM-based turn detection that doesn't cut on breath pauses (the silence-based `server_vad` is kept as fallback at `silence_duration_ms: 1500`).

### Bridge sync architecture
- Soniox sliding-window merger keeps a single growing transcript; bubbles render the per-turn suffix beyond `sonioxTurnStartMark`.
- Turn boundary commits on the **next** `speech_started`, not on `response.done` — Soniox's late finalizations (1–5 s after audio) stay attached to the closing bubble instead of creating a phantom new one.
- `response.done(cancelled)` is ignored — a 70 ms breath gap can't split one utterance into two bubbles.
- 6-second Soniox warm-up grace prevents OpenAI input deltas from briefly flashing a sentence in the bubble before Soniox catches up.
- Language-based bubble placement: Cyrillic → langA-side column, Spanish-diacritic / Latin → langB-side column. Bubbles don't all stack on one side.
- Auto-scroll on new bubbles AND on streaming text growth.

### Observability
- `DiagLogger` ring buffer (500 lines, accessible from any LogPanel) with `os.Logger` bridge.
- `RemoteLogger` ships every entry to `POST /api/logs` with a stable per-install `deviceID`. Curl-friendly:
  ```bash
  curl -s "https://89-167-19-222.sslip.io/api/logs?limit=200&deviceID=<id>"
  ```
- Audio archive: each Bridge session's WAV is auto-uploaded to `POST /api/recordings`. Listable + downloadable via the same hostname.

### Cost guard
The 7 kill triggers ported verbatim from the Mini App, with `+2 min` deadline extension via the Continue button:

| Trigger | Cause |
|---|---|
| Manual | User taps Stop |
| Deadline | 3-min auto-stop |
| PeerConnection failed | WebRTC error |
| PeerConnection closed | Remote close |
| Background grace | Backgrounded for 5 s |
| App terminate | `willTerminateNotification` |
| Watchdog | Leaked resources detected while idle |

---

## Prerequisites

- macOS with Xcode 16+ (verified on 26.4.1).
- iOS 17+ Simulator runtime (auto-downloaded on first run via `xcodebuild -downloadPlatform iOS`).
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) — generates the `.xcodeproj` from `project.yml`.

```bash
brew install xcodegen
```

## Setup

```bash
cd ios/TeycanTranslate
xcodegen generate
open TeycanTranslate.xcodeproj
```

In Xcode: select an iOS 17+ simulator → ⌘R. First launch shows the Sign-in-with-Apple screen. In `DEBUG` builds there's a "Continue without sign-in" button so you can exercise the tabs without an Apple Developer account.

To run the test suite from CLI:

```bash
xcodebuild test \
  -project TeycanTranslate.xcodeproj \
  -scheme TeycanTranslate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""
```

## Deploy to physical iPhone

Free Apple Developer Personal Team flow — see `CLAUDE.md` for the one-shot deploy script. TL;DR:

```bash
xcodebuild -project TeycanTranslate.xcodeproj -scheme TeycanTranslate \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_UDID" \
  -derivedDataPath ./build -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=$TEAM_ID build && \
xcrun devicectl device install app --device $DEVICE_UDID \
  ./build/Build/Products/Debug-iphoneos/TeycanTranslate.app && \
xcrun devicectl device process launch --device $DEVICE_UDID \
  solutions.techchain.teycan.translate
```

Free-tier builds expire 7 days after signing — re-run the deploy to refresh.

## Project layout

```
ios/TeycanTranslate/
├── project.yml                   # xcodegen spec — THE source of truth
├── TeycanTranslate.entitlements  # signing entitlements
├── Sources/
│   ├── App/                      # @main, AppRoot → AuthGate → MainTabView
│   ├── Auth/                     # Apple Sign In: coordinator, store, view, Keychain
│   ├── Networking/               # APIClient + JWT injection + DTOs
│   ├── Audio/                    # AVAudioSession config, PCMStreamRecorder, MP3 player
│   ├── STT/                      # SonioxLiveSTT (WS streaming) + SlidingWindowMerger
│   ├── WebRTC/                   # PeerFactory, RealtimeRTCClient, RealtimeEvent decoder
│   ├── CostGuard/                # 7-layer kill switch
│   ├── Persistence/              # UserDefaults key constants
│   ├── Logger/                   # DiagLogger ring buffer + RemoteLogger HTTP shipper
│   ├── DesignSystem/             # Colors, Typography, MicButton, LogPanel, DeadlineBanner
│   └── Features/
│       ├── Phrase/               # one-shot record → transcribe → translate → speak
│       ├── Companion/            # gpt-realtime-translate WebRTC, AirPods-gated
│       └── Bridge/               # gpt-realtime conversational + Soniox parallel STT + language-side detection + auto-scroll
├── Tests/                        # 129 XCTest cases
└── Resources/                    # Info.plist, Assets.xcassets, fonts (JetBrains Mono bundled)
```

## Backend additions

The Express backend (in the parent `ai-translator/` repo) ships these endpoints used by this iOS app:

- `POST /api/auth/apple` — verifies Apple `identityToken` against JWKS, returns 30-day JWT.
- `GET  /api/token` — short-lived Soniox temporary API key.
- `POST /api/realtime/session` — mint `gpt-realtime-translate` `client_secret` (Companion).
- `POST /api/realtime-chat/session` — mint `gpt-realtime` `client_secret` with `semantic_vad` config (Bridge).
- `POST /api/translate-auto` — Groq translation for Phrase fallback.
- `POST /api/tts` — ElevenLabs TTS for Phrase.
- `POST /api/logs` + `GET /api/logs?deviceID=…` — remote DiagLogger ring buffer.
- `POST /api/recordings` + `GET /api/recordings/file?deviceID=…&name=…` — per-session WAV archive.

## Offline analysis pipeline

Each Bridge session uploads its raw WAV. To analyze a saved recording end-to-end:

```bash
# 1. List recordings for a device
curl -s "https://89-167-19-222.sslip.io/api/recordings?deviceID=<id>"

# 2. Download a specific WAV
curl -s "https://89-167-19-222.sslip.io/api/recordings/file?deviceID=<id>&name=<file>.wav" -o /tmp/x.wav

# 3. Run Gemini (timestamps) + Soniox-async (accurate text) compare
node ../scripts/compare-transcripts.js /tmp/x.wav
# Outputs: { gemini, soniox, similarity_ratio, char_diff_count }
```

This pipeline is what we used to chase down the AVAudioConverter zero-frame bug and the Soniox/gpt-realtime turn-boundary races.

## Known scope deltas

- **Live tab** (multi-stream Soniox demo) is intentionally not ported — superseded by Companion/Bridge.
- Free-tier Apple Developer Program: TestFlight not available, app expires every 7 days. No push, no IAP, no iCloud, no Associated Domains.
- Ukrainian as Companion target falls back to Russian (the `gpt-realtime-translate` model can't synthesize Ukrainian audio yet — same constraint as the Mini App).

## Changelog (recent)

**v1.0 (this release)**

- Soniox parallel STT on Bridge with proper sync architecture (turn boundary commits on `speech_started`, not `response.done`).
- DefaultPrompt v9: strict-translator preamble + parametric langA/langB + banned-greetings list.
- OpenAI Realtime VAD switched from `server_vad`/500 ms to `semantic_vad`/eagerness=low to stop premature cutoffs on long utterances.
- Language-based bubble placement on Bridge (Cyrillic ↔ Latin column detection).
- Auto-scroll on Bridge for streaming + new bubbles.
- Audio routing: built-in mic preferred, main loudspeaker forced (with AirPods opt-out).
- RemoteLogger → `POST /api/logs` for over-the-wire debugging.
- WAV archive → `POST /api/recordings` for offline Gemini + Soniox-async comparison.
- AVAudioConverter zero-frame bug fixed (`.endOfStream` → `.noDataNow` + bigger output capacity).
- `response.done(cancelled)` no longer splits one utterance into multiple bubbles.
- 6-second Soniox warm-up grace prevents OpenAI flash before Soniox catches up.
- New dog wordmark icon.

**v0.x (earlier phases)**

- Phase 1–5 (skeleton → Phrase/Companion/Bridge ports) — see `git log` for details.
