# iOS — Deploy & Build Guide

Native SwiftUI iOS app (`TeycanTranslate`). Generated from `project.yml` via [xcodegen](https://github.com/yonaskolb/XcodeGen). Code-signed with **free Apple Developer (Personal Team)** — no paid program needed.

## Quick context (state as of 2026-05-09)

- **Target device:** iPhone 14 Pro "iPhone Serbinow 🐼"
- **Device UDID (CoreDevice):** `B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA`
- **Apple ID:** `bolotnya@mail.ru` (Personal Team)
- **DEVELOPMENT_TEAM:** `JBZQPPB4YV`
- **Bundle ID:** `solutions.techchain.teycan.translate`
- **Signing identity:** `Apple Development: bolotnya@mail.ru (6P823D3785)`
- **Sign in with Apple capability:** **disabled** (free Personal Team can't use it). Use Debug build's "Continue without sign-in" button to bypass AuthGate.

## When the user says "deploy" or "deploy to iPhone"

Run this single command — it builds, installs, and launches in one shot:

```bash
cd /Users/serbinov/Desktop/projects/ai-translator/ios/TeycanTranslate && \
xcodebuild -project TeycanTranslate.xcodeproj -scheme TeycanTranslate \
  -configuration Debug \
  -destination 'platform=iOS,id=B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA' \
  -derivedDataPath ./build -allowProvisioningUpdates build && \
xcrun devicectl device install app --device B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA \
  ./build/Build/Products/Debug-iphoneos/TeycanTranslate.app && \
xcrun devicectl device process launch --device B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA \
  solutions.techchain.teycan.translate
```

If the device isn't connected/available, check with:

```bash
xcrun devicectl list devices
```

State should be `connected` or `available (paired)`. If `unavailable` — ask user to unlock iPhone, plug it in, tap "Trust This Computer" if prompted.

## Individual steps (if user wants partial action)

### Build only (no install)

```bash
cd /Users/serbinov/Desktop/projects/ai-translator/ios/TeycanTranslate && \
xcodebuild -project TeycanTranslate.xcodeproj -scheme TeycanTranslate \
  -configuration Debug \
  -destination 'platform=iOS,id=B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA' \
  -derivedDataPath ./build -allowProvisioningUpdates build
```

Output: `./build/Build/Products/Debug-iphoneos/TeycanTranslate.app`

### Install (assumes build is fresh)

```bash
xcrun devicectl device install app --device B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA \
  /Users/serbinov/Desktop/projects/ai-translator/ios/TeycanTranslate/build/Build/Products/Debug-iphoneos/TeycanTranslate.app
```

### Launch only (already installed)

```bash
xcrun devicectl device process launch --device B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA \
  solutions.techchain.teycan.translate
```

### Launch with live console logs (for debugging)

```bash
xcrun devicectl device process launch --device B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA \
  --console solutions.techchain.teycan.translate
```

### Uninstall

```bash
xcrun devicectl device uninstall app --device B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA \
  solutions.techchain.teycan.translate
```

### Regenerate Xcode project from `project.yml`

After editing `project.yml`:

```bash
cd /Users/serbinov/Desktop/projects/ai-translator/ios/TeycanTranslate && xcodegen generate
```

## When the user says "run on simulator"

```bash
cd /Users/serbinov/Desktop/projects/ai-translator/ios/TeycanTranslate && \
xcodebuild -project TeycanTranslate.xcodeproj -scheme TeycanTranslate \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ./build build && \
xcrun simctl install booted ./build/Build/Products/Debug-iphonesimulator/TeycanTranslate.app && \
xcrun simctl launch booted solutions.techchain.teycan.translate
```

## When the user says "run tests"

```bash
cd /Users/serbinov/Desktop/projects/ai-translator/ios/TeycanTranslate && \
xcodebuild test -project TeycanTranslate.xcodeproj -scheme TeycanTranslate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""
```

64 unit tests should pass.

## Free Personal Team — important constraints

| Constraint | Detail |
|---|---|
| **App lifetime** | **7 days** from build. After expiry app refuses to launch ("Unable to verify app"). Re-deploy to refresh. |
| **App ID slots** | Max 3 simultaneous app IDs per Apple ID. Reuse the existing one. |
| **Sign in with Apple** | Disabled in this project. Don't re-add `com.apple.developer.applesignin` unless user upgrades to paid program. |
| **Push, iCloud, IAP, Associated Domains** | Not available on free tier. Don't add these capabilities. |
| **TestFlight / App Store** | Not possible. Distribution to others requires either: physical USB to this Mac + Xcode signing, or third-party tools (SideStore/AltStore). |
| **Provisioning profile** | Auto-managed via `-allowProvisioningUpdates`. Profile lives at `~/Library/MobileDevice/Provisioning Profiles/`. |
| **Developer Mode on iPhone** | Must stay enabled: Settings → Privacy & Security → Developer Mode → On. |

## Troubleshooting

### `Developer Mode disabled` during build
On iPhone: Settings → Privacy & Security → Developer Mode → On → reboot device.

### `Unable to launch ... invalid code signature ... profile has not been explicitly trusted`
On iPhone: Settings → General → VPN & Device Management → "Apple Development: bolotnya@mail.ru" → **Trust**. Then re-launch.

### Device shows `unavailable` in `devicectl list devices`
- Unlock iPhone (must be unlocked for some devicectl ops)
- If first connect after reboot: tap "Trust This Computer" on iPhone, enter PIN
- Replug USB cable

### Build error `provisioning profile doesn't include the X entitlement`
A capability was added that free tier doesn't support. Either remove it from `TeycanTranslate.entitlements` (and `project.yml` if referenced) or upgrade to paid Apple Developer Program ($99/year).

### Build error after editing `project.yml`
Forgot to regenerate. Run `xcodegen generate` in `ios/TeycanTranslate/`.

### App expired (7 days passed)
Just run "deploy" again — re-signs and re-installs with fresh 7-day window.

## File layout (relevant for deploy)

```
ios/
├── CLAUDE.md                                # this file
├── README.md                                # project-level overview
└── TeycanTranslate/
    ├── project.yml                          # xcodegen spec — source of truth
    ├── TeycanTranslate.entitlements         # signing entitlements (currently empty)
    ├── TeycanTranslate.xcodeproj/           # generated by xcodegen, gitignored
    ├── Sources/                             # Swift code
    ├── Resources/                           # Info.plist, Assets.xcassets
    ├── Tests/                               # 64 XCTest cases
    └── build/                               # derivedData, gitignored
```

## How signing was set up (one-time, already done)

1. Apple ID added in Xcode → Settings → Accounts (creates Personal Team)
2. Project opened in Xcode → TeycanTranslate target → Signing & Capabilities
3. "Automatically manage signing" enabled, Team set to Personal Team
4. Xcode auto-generated certificate + provisioning profile on first build
5. Developer Mode enabled on iPhone, developer profile trusted in Settings

If signing breaks (e.g. cert expired, new device), re-do steps 2–5 in Xcode UI. CLI alone can't bootstrap a brand-new Personal Team cert.

---

## Audio Testing — Voice Translator QA

This app's core feature is voice translation (Voice tab + Realtime tab + Chat tab — all process audio). To let an AI agent verify the full voice flow autonomously, we route a pre-recorded audio file into the iOS Simulator's microphone via **BlackHole** (virtual audio device on macOS), then read the translated result via UI introspection.

### When the user says "test voice flow" / "потестуй голосовий флоу" / "test audio translation"

Follow this end-to-end procedure for each scenario in `TeycanTranslate/Tests/AudioFixtures/`.

#### Prerequisites (one-time setup — check before running tests)

1. **BlackHole 2ch installed:**
   ```bash
   brew list blackhole-2ch >/dev/null 2>&1 || brew install blackhole-2ch
   ```
2. **macOS audio routing configured** — Audio MIDI Setup → Create Multi-Output Device with BlackHole + built-in speakers (so user can still hear). Then set BlackHole as system default input. Verify:
   ```bash
   SwitchAudioSource -t input -c    # should output "BlackHole 2ch"
   # If not, install: brew install switchaudio-osx
   SwitchAudioSource -t input -s "BlackHole 2ch"
   ```
3. **Simulator booted** with TeycanTranslate installed:
   ```bash
   xcrun simctl list devices | grep "Booted" || xcrun simctl boot "iPhone 17 Pro"
   open -a Simulator
   ```

#### Per-test procedure (one fixture)

```bash
# 1. Route mic input to BlackHole (so simulator gets file audio, not real mic)
SwitchAudioSource -t input -s "BlackHole 2ch"

# 2. Launch app fresh on simulator
xcrun simctl terminate booted solutions.techchain.teycan.translate
xcrun simctl launch booted solutions.techchain.teycan.translate

# 3. Use XcodeBuildMCP (or simctl) to tap Voice tab + tap mic button
#    (coords from snapshot_ui — find "Voice" tab + "Record" button accessibility labels)

# 4. Play fixture INTO BlackHole (simulator sees this as mic input)
afplay -d "BlackHole 2ch" TeycanTranslate/Tests/AudioFixtures/hello-uk.m4a

# 5. Wait for processing (ElevenLabs STT + Gemini translation + TTS)
sleep 8

# 6. Capture translated text via snapshot_ui (XcodeBuildMCP)
#    Look for accessibility label of translation output TextView

# 7. Take screenshot for visual diff
xcrun simctl io booted screenshot ./test-output/hello-uk-result.png

# 8. (Optional) Record audio output — for verifying TTS quality
xcrun simctl io booted recordVideo --codec=h264 ./test-output/hello-uk-tts.mov
# After tapping "play" on translated audio:
# ffmpeg -i hello-uk-tts.mov -vn -acodec libmp3lame hello-uk-tts.mp3
# Pass to STT to verify TTS pronunciation

# 9. Restore real mic when done
SwitchAudioSource -t input -s "MacBook Pro Microphone"
```

#### Audio fixtures layout

```
TeycanTranslate/Tests/AudioFixtures/
├── hello-uk.m4a       — "Привіт, як справи сьогодні?" (~3s, Ukrainian)
├── hello-es.m4a       — "Hola, ¿cómo estás hoy?" (~3s, Spanish)
├── hello-en.m4a       — "Good morning, how are you today?" (~3s, English)
├── long-uk.m4a        — multi-sentence Ukrainian (~10s)
├── long-es.m4a        — multi-sentence Spanish (~10s)
├── noisy-uk.m4a       — Ukrainian in noisy environment (edge case)
└── expected.json      — expected translations per fixture (see schema below)
```

`expected.json` schema (agent reads this to validate results):
```json
{
  "hello-uk.m4a": {
    "detectedLanguage": "uk",
    "transcribed": "Привіт, як справи сьогодні?",
    "translations": {
      "es": "Hola, ¿cómo estás hoy?",
      "en": "Hi, how are you today?"
    }
  }
}
```

When user adds a new fixture, also add its entry to `expected.json`.

#### Validation rules (agent must enforce)

- **STT accuracy:** transcribed text should match `expected.transcribed` with ≥85% character similarity (whitespace + punctuation tolerated). Use Python's `difflib.SequenceMatcher` if needed.
- **Language detection:** `detectedLanguage` must match exactly. Mismatch = critical failure.
- **Translation:** check that translated text contains the key content words from `expected.translations[lang]`. Don't require exact match (translation is non-deterministic across Gemini calls), but semantic equivalence.
- **Latency:** end-to-end (mic stop → translated text visible) should be < 6s for short fixtures, < 15s for long. Anything beyond = degraded performance warning.
- **No crashes:** monitor simulator logs (`xcrun simctl spawn booted log stream --predicate 'process == "TeycanTranslate"'`) during test. Any crash = critical failure.

#### Known limitations

- **Real iPhone testing:** BlackHole approach is macOS-only — it works for **simulator only**. To test on physical iPhone, route audio via Bluetooth audio receiver or play the file on a separate device near the iPhone (manual). Not automatable.
- **Realtime tab (WebRTC):** routes audio directly to OpenAI servers. BlackHole works the same way — simulator's mic is fed file audio, which streams to OpenAI. Validation is via screenshots + simulator logs.
- **Chat tab (gpt-realtime with VAD):** same as Realtime but with VAD turn-taking. Tricky to test because VAD waits for silence — keep fixtures with clear silence padding at end.

#### Reset / cleanup after testing

```bash
# Restore real microphone for normal use
SwitchAudioSource -t input -s "MacBook Pro Microphone"

# Kill app
xcrun simctl terminate booted solutions.techchain.teycan.translate
```

If user reports microphone not working in other apps after a test session — that's the leftover BlackHole routing. Run the restore command above.

#### Adding new fixtures

When user records a new audio sample:

1. Save the file to `TeycanTranslate/Tests/AudioFixtures/<descriptive-name>.<ext>` (m4a/wav/mp3 all work).
2. Add entry to `expected.json` with `detectedLanguage`, `transcribed`, and at least 2 target-language translations.
3. Commit and push to `teycan-translate-ios` repo.
4. Run the per-test procedure to verify the new fixture works end-to-end.

---

### Agent Runbook for Cold-Start (READ THIS FIRST)

**Purpose:** If you are an AI agent reading this file with zero prior context, this section walks you end-to-end through running the voice test. Follow it literally.

#### App overview (what you're testing)

TeycanTranslate is a **3-tab voice translator**:

| Tab | Internal name | What it does | Use for |
|---|---|---|---|
| **Phrase** | `phrase` (was "Voice") | Tap mic → record → STT → translate → TTS playback. One-shot. | Testing `hello-*.wav` fixtures end-to-end. |
| **Companion** | `companion` (was "Realtime") | Continuous live listening via gpt-realtime-translate WebRTC. Streams. | Testing real-time translation latency. |
| **Bridge** | `bridge` (was "Chat") | Two-way conversational, with VAD and editable system prompt. **Default landing tab.** | Testing dialogue / turn-taking. |

**Launch flag** to jump directly to a tab — saves UI navigation:
```
-start-tab phrase   |   -start-tab companion   |   -start-tab bridge
```

#### Known accessibility labels (use these for tapping)

| Element | Label | Where |
|---|---|---|
| Mic button (idle) | `Start` | Phrase, Companion, Bridge — center bottom |
| Mic button (recording) | `Stop` | same place, different state |
| Clear text | `Clear` | Phrase tab |
| Copy translation | `Copy translation` | Phrase tab (next to translated text) |
| Swap source/target languages | `Swap languages` | top of Phrase / Bridge |
| Edit system prompt | `Edit system prompt` | Bridge tab |
| Continue session (+2 min) | `Continue session for two more minutes` | Companion/Bridge deadline banner |

For anything else — call XcodeBuildMCP's UI snapshot tool first; never guess coords.

#### Preflight checklist (run these in order, fix as you go)

```bash
# 1. Are we on the right machine? (BlackHole + simctl are macOS-only)
test "$(uname)" = "Darwin" || { echo "ABORT: macOS required"; exit 1; }

# 2. Is XcodeBuildMCP available? Ask your harness to list MCP tools containing "xcodebuild" — if none, tell user to run:
#    claude mcp add xcodebuild -s user -- npx -y xcodebuildmcp@latest mcp
#    then restart Claude Code.

# 3. Xcode + simctl
xcode-select -p >/dev/null || { echo "ABORT: install Xcode CLT"; exit 1; }
xcrun simctl help >/dev/null

# 4. BlackHole virtual audio device
brew list blackhole-2ch >/dev/null 2>&1 || brew install blackhole-2ch
brew list switchaudio-osx >/dev/null 2>&1 || brew install switchaudio-osx

# 5. Confirm BlackHole is selectable as input
SwitchAudioSource -a -t input | grep -q "BlackHole 2ch" || \
  { echo "ABORT: BlackHole installed but not registered. Reboot or relaunch coreaudiod: sudo killall coreaudiod"; exit 1; }

# 6. Audio fixtures present
FIXTURES="/Users/serbinov/Desktop/projects/ai-translator/ios/TeycanTranslate/Tests/AudioFixtures"
ls "$FIXTURES"/hello-uk.wav "$FIXTURES"/hello-es.wav "$FIXTURES"/expected.json >/dev/null || \
  { echo "ABORT: fixtures missing"; exit 1; }

# 7. Simulator booted with a recent iPhone
xcrun simctl list devices | grep "Booted" || xcrun simctl boot "iPhone 17 Pro"
open -a Simulator

# 8. App installed on booted sim (build first if not)
xcrun simctl get_app_container booted solutions.techchain.teycan.translate >/dev/null 2>&1 || \
  echo "WARNING: app not installed — run 'deploy to simulator' procedure first"
```

If anything in the preflight fails — **stop and tell user with the exact failing step**. Do not try to bypass.

#### One-fixture test cycle (do this for each fixture)

Example below uses `hello-uk.wav`. Repeat for `hello-ru.wav`, `hello-es.wav`.

**Step A — set up audio routing:**

```bash
# Remember the user's normal mic so we can restore it at the end
ORIGINAL_INPUT=$(SwitchAudioSource -c -t input)
echo "$ORIGINAL_INPUT" > /tmp/teycan-original-input

# Route system input to BlackHole — simulator now "hears" whatever we play to BlackHole
SwitchAudioSource -t input -s "BlackHole 2ch"
```

**Step B — launch app on a specific tab:**

```bash
xcrun simctl terminate booted solutions.techchain.teycan.translate 2>/dev/null || true
xcrun simctl launch booted solutions.techchain.teycan.translate -start-tab phrase
sleep 2  # let UI settle
```

**Step C — find the mic button + tap "Start" via XcodeBuildMCP:**

Use the MCP's UI-snapshot tool (in XcodeBuildMCP v2.5.1 it's typically `ui-automation/describe_ui` or similar — discover the exact name by listing tools). The snapshot returns a JSON tree with elements that have `label`, `frame: {x, y, width, height}`. Find the element where `label == "Start"`. Get its center: `cx = frame.x + frame.width/2`, `cy = frame.y + frame.height/2`. Then call the MCP's `tap` tool with `(cx, cy)`.

If UI snapshot returns nothing useful (e.g. it's a permission dialog on first launch), call `screenshot` first to see what's on screen. Common first-launch dialogs: microphone permission ("Allow", "Don't Allow"), Sign in with Apple (use "Continue without sign-in" — it's a debug-only button). Tap "Allow" / "Continue" as appropriate, then retry.

**Step D — play the audio into BlackHole (simulator's mic captures it):**

```bash
afplay -d "BlackHole 2ch" "$FIXTURES/hello-uk.wav"
# afplay blocks until playback finishes — when it returns, the app has finished receiving "mic input"
```

**Step E — tap "Stop" to finalize recording (if app needs explicit stop):**

In Phrase tab, after `afplay` returns there's a small silence — the app may auto-detect end of speech, OR it waits for "Stop" tap. Check both: take a screenshot. If mic button label is still "Stop" (recording), tap it. If it's already back to "Start", the app auto-stopped.

```bash
sleep 1
# (Use MCP screenshot → if label is still "Stop", tap to stop)
```

**Step F — wait for translation to complete and read the result:**

The app calls ElevenLabs Scribe v2 → translation service (Gemini or Groq depending on `TRANSLATION_PROVIDER`) → ElevenLabs TTS. Total round-trip ~3–8s for short fixtures, 5–15s for long. Poll the UI:

```bash
for i in $(seq 1 20); do
  sleep 1
  # Use MCP ui-snapshot to find a Text element near the bottom containing translated text
  # If found and stable for 2 consecutive polls → done
done
```

Capture both:
- **Translated text** — read via UI snapshot. The Phrase tab shows transcribed source (top) and translated target (bottom). Extract both strings.
- **Screenshot** — save to `./test-output/hello-uk-result.png` for visual diff and human review.

**Step G — validate against `expected.json`:**

Load `Tests/AudioFixtures/expected.json` and compare:

| Field | Rule | If mismatch |
|---|---|---|
| `detectedLanguage` | Exact match | **Critical fail** — log + screenshot + continue |
| `transcribed` | ≥85% character similarity (Python `difflib.SequenceMatcher.ratio()`). Whitespace + punctuation tolerated. | **Soft fail** — log diff, continue |
| `translations[currentTargetLang]` | Contains ≥60% of the key content words from expected. Translation is non-deterministic — don't require exact match. | **Soft fail** — log both expected and actual, continue |
| End-to-end latency | < 6s for short fixtures, < 15s for long (`long-*` filenames) | **Warning** — log, don't fail |
| Simulator log scan | No `crash`, `fatal`, `exception` keywords during the test window | **Critical fail** — print last 50 log lines, continue |

For simulator logs during the test, run in background before Step B:
```bash
xcrun simctl spawn booted log stream --predicate 'process == "TeycanTranslate"' --level=debug > /tmp/teycan-test.log &
LOG_PID=$!
# ... do steps B-F ...
kill $LOG_PID 2>/dev/null
grep -iE "crash|fatal|exception|nserror" /tmp/teycan-test.log | head -20
```

**Step H — restore mic and move to next fixture:**

```bash
SwitchAudioSource -t input -s "$(cat /tmp/teycan-original-input)"
# Then loop back to Step A with next fixture
```

#### Cleanup (always run at the end of the test session)

```bash
SwitchAudioSource -t input -s "$(cat /tmp/teycan-original-input 2>/dev/null || echo 'MacBook Pro Microphone')"
xcrun simctl terminate booted solutions.techchain.teycan.translate 2>/dev/null || true
rm -f /tmp/teycan-original-input /tmp/teycan-test.log
```

If you skip this and user's mic stays on BlackHole, every voice call / Zoom / Telegram audio on their Mac will be silent until they manually switch back. Always restore.

#### Report format (what to print to the user)

When the test completes, output exactly this structure (markdown):

```markdown
## Voice flow test — <timestamp>

### Setup
- BlackHole: <ok / installed now / failed>
- Simulator: <iPhone 17 Pro / other>
- App build: <fresh / existing>

### Results

| Fixture | Lang detect | STT accuracy | Translation | Latency | Crashes | Verdict |
|---------|-------------|--------------|-------------|---------|---------|---------|
| hello-uk.wav | uk ✅ | 96% ✅ | ok ✅ | 4.2s ✅ | none ✅ | **PASS** |
| hello-ru.wav | ru ✅ | 89% ✅ | drift ⚠️ | 5.1s ✅ | none ✅ | **WARN** |
| hello-es.wav | es ✅ | 100% ✅ | ok ✅ | 3.0s ✅ | none ✅ | **PASS** |

### Notable findings
- (e.g.) `hello-ru.wav` translation dropped the filler "э-э" — expected behavior, not a bug
- (e.g.) Companion tab took 1.2s longer than Phrase for same fixture — investigate WebRTC handshake

### Screenshots
- `./test-output/hello-uk-result.png`
- `./test-output/hello-ru-result.png`
- `./test-output/hello-es-result.png`
```

If user did NOT ask for a write-up — keep it brief: "3/3 passed, 1 warning on hello-ru (filler drop). Screenshots in `./test-output/`. Cleanup done." Don't dump the full table unless useful.

#### Common failures and what to do

| Symptom | Likely cause | Fix |
|---|---|---|
| `afplay` plays but app shows silence | System input not routed to BlackHole. | `SwitchAudioSource -c -t input` should print "BlackHole 2ch". Re-run setup step. |
| App permission dialog blocks UI | First-launch microphone permission. | Tap "Allow" via MCP. App restart not needed. |
| AuthGate "Sign in with Apple" screen | Free Personal Team can't use Sign in with Apple. | Tap "Continue without sign-in" — visible only in DEBUG build. If button absent, you have a Release build — rebuild with Debug config. |
| App crashes on launch with signing error | Provisioning profile expired (7-day free-tier limit). | Run the "deploy" procedure from top of this file to re-sign and reinstall. |
| `xcrun simctl get_app_container` fails | App not installed on booted simulator. | Build for simulator destination (see "run on simulator" section), then install: `xcrun simctl install booted <path>`. |
| MCP `tap` does nothing | Coords from old snapshot are stale. | Re-snapshot UI right before each tap, never reuse old coords. |
| Translation never appears | Backend (`https://89-167-19-222.sslip.io`) is down, or app pointed at wrong env. | `curl -I https://89-167-19-222.sslip.io/webapp/index.html` should return 200. If app points at localhost, set `BACKEND_BASE_URL` env var on simulator: `xcrun simctl launch booted ... --env BACKEND_BASE_URL=https://...` |
| Audio plays through Mac speakers as well as into sim | Multi-Output device routes audio everywhere (intentional). | This is fine — BlackHole still captures it. If user complains about noise, suggest temporarily muting Mac speakers via Volume key. |

#### What you should NEVER do

- **Don't tap on coordinates you didn't get from a fresh UI snapshot.** UI rebuilds change positions.
- **Don't skip the audio routing restoration** (`SwitchAudioSource -t input -s "$ORIGINAL_INPUT"`). The user will get silent mic in Zoom and blame you.
- **Don't modify `expected.json`** to "make tests pass". If real output differs, log the diff and let user decide whether expected or actual is wrong.
- **Don't commit changes** unless the user explicitly says "commit" or "push" (per global git policy).
- **Don't enable physical iPhone testing for voice flow** — BlackHole is Mac-only. If user requests "test voice on my iPhone", explain that automated mic injection isn't possible on a physical device with a free Apple Developer account and offer manual testing instead.


