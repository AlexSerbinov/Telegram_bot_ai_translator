# V9 Bridge Redesign — Implementation Handoff

**Date:** 2026-05-12
**Branch:** `design/v1-editorial-strict-forest`
**Status:** Implementation complete, deployed to iPhone, **NOT committed** (per project git policy — requires explicit user approval). User reports "many bugs" on real-audio testing — this doc is the handoff to the debugging agent.

---

## 1. Context: what V9 is and why it exists

The Bridge tab is the "two-way mediator" mode — UA person and ES person face the phone, model translates between them in real-time via `gpt-realtime-translate` over WebRTC. The pre-V9 layout had a flat `LangPill / LangSwapButton / LangPill` row + a small isolated `ModelNode` in the conversation stage's center, with messages as alternating bubbles.

**Problems addressed by V9:**

1. The translator entity ("M") was visually invisible. Users had no sense of "where the AI is" in the flow.
2. The realtime conversation cycle (UA speaks → M generates → ES hears → ES speaks → ...) had **no visible state in the UI**. Every gpt-realtime event was silently consumed.
3. Specifically, `output_audio_buffer.started` was parsed in `RealtimeEvent.swift` but ignored in `BridgeSessionManager.swift` (`break` statement). This event marks when M starts speaking audio out to the target — a critical visual cue.

**V9 hybrid:** Top half = V7 "conductor" stage (3 actors + animated dataflow + central haloed M with orbital dots). Bottom half = V5-style provenance cards (`UA → M → ES   02:47 · 0.8s` + source text + hairline + translation + copy button).

Design specs and previously approved demos live in:

- `docs/design/bridge-redesign/INDEX.md` (variant matrix)
- `docs/design/bridge-redesign/FEASIBILITY.md` (pre-implementation feasibility analysis — read this first to understand what we expected from the code)
- `docs/design/bridge-redesign/demos/v9-hybrid.html` (interactive HTML demo with state controls)

---

## 2. Files changed

### Modified (3 files)

| File | What changed |
|---|---|
| `ios/TeycanTranslate/Sources/Features/Bridge/BridgeSessionManager.swift` | Added `CyclePhase` + `ConductorSide` enums; added `cyclePhase`, `sessionStartedAt`, `lastSpeechStoppedAt`, `latencyByItemID` published fields; wired `speech_started/stopped`, `outputTranscriptDelta`, `outputAudioBufferStarted`, `responseDone` events to drive phase transitions; reset all new fields in `start()` / `tearDown()` |
| `ios/TeycanTranslate/Sources/Features/Bridge/BridgeMessage.swift` | Added `var createdAt: Date = Date()` (used by provenance trail to render MM:SS timestamps) |
| `ios/TeycanTranslate/Sources/Features/Bridge/BridgeView.swift` | Replaced `languagePair()` + `conversationStage()` + old `turnCard()` with `ConductorStage` at top + `archiveStack()` with `pairedTurnCard()` that merges user+assistant messages of the same turn into one card with `ProvenanceTrail` |
| `DESIGN.md` | § Three Modes > Bridge rewritten — describes ConductorStage's 5 realtime states + provenance trail |

### Created (4 files)

| File | Purpose |
|---|---|
| `ios/TeycanTranslate/Sources/DesignSystem/Components/ConductorStage.swift` | Top-of-stage composite: 3 actor capsules + dataflow strips + haloed M with orbital dots + caption box. Phase-reactive via `BridgeSessionManager.CyclePhase` |
| `ios/TeycanTranslate/Sources/DesignSystem/Components/EndpointPill.swift` | Clickable side actor (Side A / Side B). Flag + code + chevron + state label. Tap opens `BridgeLangPickerSheet` |
| `ios/TeycanTranslate/Sources/DesignSystem/Components/DataFlow.swift` | 3 animated accent dots flowing along a horizontal track. Direction-reactive (LR / RL). Active only when meaning is flowing |
| `ios/TeycanTranslate/Sources/DesignSystem/Components/ProvenanceTrail.swift` | `UA → M → ES   MM:SS · X.Ys` line in JetBrains Mono accent. Plus `CopyButton` (UIPasteboard → ✓ confirmation) |

---

## 3. State machine: CyclePhase

```swift
enum CyclePhase: Equatable {
    case idle
    case sourceListening(side: ConductorSide)   // VAD detected user speech
    case sourceFinished(side: ConductorSide)    // VAD silence
    case translating(sourceSide: ConductorSide) // M is generating
    case targetSpeaking(side: ConductorSide)    // M's audio playing
}
enum ConductorSide: Equatable { case a, b }
```

### Transition table (current implementation)

| gpt-realtime event | Code action | New `cyclePhase` |
|---|---|---|
| `input_audio_buffer.speech_started` | Compute `currentSourceSide()` from `lastUserLang` | `.sourceListening(side:)` |
| `input_audio_buffer.speech_stopped` | Stamp `lastSpeechStoppedAt = Date()` | `.sourceFinished(side:)` |
| First `response.audio_transcript.delta` after `sourceFinished` | (existing `appendDelta` logic unchanged) | `.translating(sourceSide:)` |
| `output_audio_buffer.started` | Compute target side as opposite of source | `.targetSpeaking(side:)` — **THIS EVENT WAS PREVIOUSLY UNUSED** |
| `response.done(status: "completed")` | Compute latency (`Date.now - lastSpeechStoppedAt`), store in `latencyByItemID[currentUserItemID]`, clear timestamp | `.idle` |
| `response.done(status: "cancelled")` | (existing logic: keep current turn) | (unchanged — no transition) |

### Side resolution

```swift
private func currentSourceSide() -> ConductorSide { side(forLang: lastUserLang) }
private func side(forLang lang: String?) -> ConductorSide {
    guard let lang else { return .a }
    return lang == sessionLangA ? .a : .b
}
```

**Known limitation:** when the user starts a new utterance, we set `cyclePhase = .sourceListening(side: currentSourceSide())` — but `currentSourceSide()` returns the side of the **previous** turn's `lastUserLang`. If the user changes language mid-conversation, the FIRST `sourceListening` will animate the wrong side until a transcript delta arrives and language is re-guessed.

**Possible fix to investigate:** when `inputTranscriptDelta` / Soniox handler updates `lastUserLang`, also update `cyclePhase` if it's currently `.sourceListening` to flip to the correct side.

---

## 4. Wiring + Soniox parallel STT — what to know

### Two parallel transcript paths (already shipped pre-V9, **not** added by this change)

The Bridge tab runs `gpt-realtime-translate` over WebRTC for audio translation AND a parallel `SonioxLiveSTT` WebSocket for user-side partial transcripts. Both consume the mic. The orchestration lives in `BridgeSessionManager.swift`:

- `BridgeSettings.useSoniox` (default `true`) — gates the Soniox path
- `sonioxActivelyTranscribing` — whether Soniox is currently producing tokens (warm-up grace = 6s, then 4s lookback on last token time)
- When Soniox is active, `openai.input_audio_transcription.delta` events are **suppressed** to avoid double-bubbles
- When Soniox starves (e.g. `AVAudioEngine` can't open mic alongside WebRTC), the watchdog at `BridgeSessionManager.swift:268-278` logs `WATCHDOG — Soniox armed but 0 PCM chunks after 4s` and **OpenAI partials take over** filling the user bubble

### Soniox ↔ gpt-realtime sync edge cases (already handled in code — DO NOT re-engineer unless bugs map here)

- **Phantom turn** — Soniox `is_final: true` tokens can arrive 1–5s AFTER `response.done`. If we close the turn boundary immediately, those late finalizations open a phantom new bubble. Fix in code: `sonioxAwaitingNewTurn = true` on `response.done(completed)`, then commit boundary on next `speech_started` instead (see `handle(event:)` for `.inputAudioBufferSpeechStarted`).
- **Warm-up grace** — first 6s after Soniox connects, we optimistically claim "actively transcribing" so OpenAI deltas don't race in and flash the wrong text into the user bubble before Soniox's first token arrives (~300ms typical).
- **Cancel handling** — `response.done(cancelled)` happens when user resumes speaking mid-translation. We keep the current bubble open instead of closing the turn. **In V9, I do NOT reset cyclePhase on cancel** — it stays in whatever phase was active. This might be a bug: if cancel happens during `.targetSpeaking`, we should transition back to `.sourceListening`, not stay in target-speaking forever.

### How CyclePhase interacts with Soniox

V9 layered CyclePhase **on top of** the existing Soniox logic. The phase transitions are driven exclusively by gpt-realtime data-channel events (`speech_started`, `speech_stopped`, `outputTranscriptDelta`, `outputAudioBufferStarted`, `responseDone`). Soniox events do NOT affect cyclePhase.

**Suspected bug area:** if `lastSpeechStoppedAt` is set but `response.done` never fires (network issue / connection drop / VAD misfire), `latencyByItemID` won't get populated and the provenance trail will show timestamp without latency. The UI handles `nil` latency gracefully but the timer leak could mask other bugs.

---

## 5. UI architecture

### BridgeView layout (post-V9)

```
ScrollView {
  VStack {
    header()                                  // "Bridge" + LiveIndicator + prompt-editor button
    ConductorStage(phase:, langA:, langB:,    // ← top half of stage (NEW)
                   liveCaption:, ...)
    archiveStack(settings:)                   // ← paired turn cards (NEW)
    LogPanel()                                // diagnostic log
  }
  stickyMic                                   // bottom round mic + status text
}
```

`MainTabView` owns the bottom tab bar (Phrase / Companion / Bridge) — unchanged by V9.

### ConductorStage internals

```
HStack {
  EndpointPill(Side A) ──► DataFlow ──► [M with halo + orbital dots] ──► DataFlow ──► EndpointPill(Side B)
}
[caption box below: source label + live partial text]
```

- Endpoints highlight (accent border + soft fill) when `isSideActive`
- DataFlow animates when `isFlowing(from:)`
- M shows orbital dots when `isTranslating`
- Caption box shows the last unfinalized message OR a hint text when idle

### Paired turn card (V5-style)

Each completed turn = one card containing:
1. `ProvenanceTrail` — `UA → M → ES   MM:SS · 0.8s`
2. Source text (`bodyEmphasis` ink color)
3. Hairline divider
4. Translation text (`body` muted color) + `CopyButton` (📋 → ✓)

Cards alternate left/right based on which side initiated the turn (left = Side A source, right = Side B source).

### `pairedTurns()` algorithm

The manager exposes a flat `messages: [BridgeMessage]` array alternating user/assistant. BridgeView pairs them:

```
walk messages:
  if msg.role == .user:
    if pendingUser exists → push TurnPair(user: pendingUser, assistant: nil)
    pendingUser = msg
  if msg.role == .assistant:
    if pendingUser exists → push TurnPair(user: pendingUser, assistant: msg); pendingUser = nil
    else → push TurnPair(user: nil, assistant: msg)  // orphan, shouldn't happen
if pendingUser → push final TurnPair(user: pendingUser, assistant: nil)
```

**Possible bug:** if for some reason a new user bubble opens **before** the previous assistant arrived (e.g. user starts speaking mid-translation, response cancels, etc.), the previous user turn renders as "open" (no translation, `…` placeholder) until matched. This might cause visual jitter if the orphan user message later gets a matching assistant later in the array.

---

## 6. Known / suspected bug areas

Listed in priority order. Each one is something I'd investigate first if testing reports failures.

### B1. Side flapping on first utterance

**Symptom:** first time user speaks UA, the conductor activates the wrong side (e.g. Side B) until language is detected, then flips.

**Cause:** `currentSourceSide()` uses `lastUserLang` which is `nil` on first utterance → defaults to `.a`. If the user actually spoke ES first, the pill flicks A→B once Soniox/openai detects ES.

**Fix idea:** On `inputTranscriptDelta` (or Soniox handler), if the new language differs from current `cyclePhase`'s side, update the phase to the corrected side.

### B2. Phase stuck in `.targetSpeaking` on cancel

**Symptom:** user starts speaking mid-translation, response cancels, but the conductor stage stays in `.targetSpeaking` (right pill highlighted, dataflow running) until the next `speech_started`.

**Cause:** `response.done(cancelled)` branch (BridgeSessionManager `handle(event:)`) intentionally skips the phase reset to avoid disturbing the existing turn. V9 inherits this behavior but the visual state needs to flip back somewhere.

**Fix idea:** Listen for `speech_started` and if we're not already in `.idle`, force `.sourceListening` (which we already do — but check if cancel happened, we may need to force-reset to idle before transitioning).

### B3. Latency missing when Soniox finalization is late

**Symptom:** provenance trail shows `02:47` but no `· 0.8s` latency.

**Cause:** `latencyByItemID[currentUserItemID]` keyed by user-bubble ID. If Soniox completes the user bubble AFTER `response.done`, `currentUserItemID` may have already incremented (see `sonioxTurnCounter += 1` on `speech_started`), so the latency was stored under a stale key.

**Fix idea:** Store latency under `sonioxTurnCounter` value AT TIME of `response.done`, not under the live `currentUserItemID`. Or store on the message directly.

### B4. Provenance card direction wrong when language is misdetected

**Symptom:** user speaks UA → card appears on the right side (where ES turns should go).

**Cause:** `BridgeLanguageGuesser` is script-based (Cyrillic share + Spanish hints). For very short UA utterances ("так", "ні", "ага") with little Cyrillic content, the guesser may return ES. Then `pairedTurnCard` aligns the card on the right.

**Fix idea:** Bias the guesser toward the previous turn's language for short utterances (<3 words). Or: use the assistant's translation language as the "negation" — if assistant ended up in UA, user must have spoken ES, and vice versa.

### B5. Orbital dots animation reset

**Symptom:** when phase transitions from `.translating` → `.targetSpeaking`, the orbital dots may snap or render briefly during transition.

**Cause:** `ConductorStage` re-creates `OrbitDots` view on phase change. The `withAnimation` in `onAppear` is per-instance, so a new instance restarts at 0°.

**Fix idea:** Hoist the orbit-angle state to ConductorStage and pass it in, OR use `.id(phase)` so SwiftUI keeps the same view across phase changes that share the same animation requirement.

### B6. Endpoint pill state label height jitter

**Symptom:** "speaking" / "done" / "hearing" labels have different widths → pill jumps width by a few px on transitions.

**Mitigation in code:** I set `state.uppercased()` and a fixed `frame(height: 10)`, plus `opacity(state.isEmpty ? 0 : 1)` to keep the row stable when empty. But width still varies. Consider min-width or `monospaced` font for state label.

### B7. Tap target on M

**Symptom:** user expects tapping M to open the prompt editor.

**Current behavior:** M is non-interactive. The prompt-editor button is a small `text.alignleft` icon in the top-right of the header (line `BridgeView.swift:92-100`).

**Fix idea:** Make the central M tappable too — wraps in `Button { showPromptEditor = true }`. Add a small chevron under M to signal interactivity.

### B8. Cards-with-no-assistant flicker

**Symptom:** when a user speaks and the user bubble opens, a card appears with just source text and `…` for translation. As soon as the assistant streams, that `…` is replaced with translation. Could look glitchy if user reads the card mid-stream.

**Mitigation in code:** Source text is shown with `bodyEmphasis`, translation with muted color — so the `…` looks intentional.

**Fix idea:** Hide the translation row entirely until first delta arrives. Or show a subtle spinner where the translation will appear.

### B9. Empty conductor stage on first launch

**Symptom:** on a freshly opened Bridge tab, the conductor caption says "Tap mic. M will detect language and translate to the other side." This is correct copy but may overlap with the absence of dataflow + still-rendered idle endpoints, making the screen feel busy.

**Mitigation:** consider hiding the DataFlow strips entirely when `.idle` (currently they render at 0 dots which is correct, but the empty 36pt-wide track is still there).

### B10. Side picker doesn't update lang in TURNS

**Symptom (HTML demo only):** in the V9 HTML demo, tapping a side and picking a different language updates the visible flag/code but the auto-cycle conversation still uses hardcoded UA↔ES text. In production iOS code this is fine (`BridgeSettings.langA/langB` are bound), but if you test on the demo first you may think it's broken.

---

## 7. What I verified vs. didn't verify

### ✅ Verified

- `xcodebuild` BUILD SUCCEEDED for both `iphoneos` device target and `iphonesimulator` target
- `xcrun simctl install` + `launch` works on iPhone 17 Pro simulator
- `xcrun devicectl device install + launch` works on iPhone 14 Pro device (UDID `B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA`)
- ConductorStage renders correctly on simulator (screenshot at `/tmp/v9-bridge-loaded.png` from session)
- UI hierarchy snapshot confirms Side A/B are tappable buttons with accessibility labels "Side A: uk. Tap to change language." (and equiv for B)
- All **129 unit tests pass** (was 64 in `ios/CLAUDE.md` — docs outdated, codebase has grown). No regressions from V9 changes
- Auth bypass via `-bypass-auth` launch flag works
- Startup logs clean — no errors, no crashes, no Swift warnings

### ❌ Not verified (USER REPORTS BUGS HERE)

- End-to-end real audio test: tap mic → speak UA → see translation flow through phases → archived card with provenance + latency. **The user attempted this manually on iPhone and reports many bugs.** Their console log was not captured before they reported back.
- Tap on flag emoji opens picker (works in HTML demo, untested on device).
- Copy button on translation actually puts text on clipboard.
- Mid-utterance cancel (B2 above) — what does the UI look like during a real cancel?
- Side picker change mid-session — does the conductor stage update?
- Long utterance (>30s) — does anything timeout?

---

## 8. How to test

### Quick smoke test (simulator)

```bash
cd /Users/serbinov/Desktop/projects/ai-translator/ios/TeycanTranslate
xcodegen generate
xcodebuild -project TeycanTranslate.xcodeproj -scheme TeycanTranslate \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ./build-sim CODE_SIGNING_ALLOWED=NO build
xcrun simctl install booted ./build-sim/Build/Products/Debug-iphonesimulator/TeycanTranslate.app
xcrun simctl launch booted solutions.techchain.teycan.translate -bypass-auth -start-tab bridge
xcrun simctl io booted screenshot /tmp/v9-test.png
open /tmp/v9-test.png
```

### Deploy to physical iPhone

```bash
cd /Users/serbinov/Desktop/projects/ai-translator/ios/TeycanTranslate
xcodegen generate  # in case any new files were added
xcodebuild -project TeycanTranslate.xcodeproj -scheme TeycanTranslate \
  -configuration Debug \
  -destination 'platform=iOS,id=B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA' \
  -derivedDataPath ./build -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=JBZQPPB4YV CODE_SIGN_STYLE=Automatic build
xcrun devicectl device install app --device B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA \
  ./build/Build/Products/Debug-iphoneos/TeycanTranslate.app
xcrun devicectl device process launch --device B0BFC1D3-0151-5AEC-A8CC-6CD92B7BEAFA \
  --terminate-existing solutions.techchain.teycan.translate -- -start-tab bridge
```

### Run unit tests

```bash
cd /Users/serbinov/Desktop/projects/ai-translator/ios/TeycanTranslate
xcodebuild test -project TeycanTranslate.xcodeproj -scheme TeycanTranslate \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""
```

Expected: 129/129 pass.

### Get logs from device (for debugging the bugs)

The app has both `DiagLogger` (in-app log buffer rendered by `LogPanel`) and `RemoteLogger` (sends to server). To pull device logs:

1. In-app: scroll Bridge tab, find DIAG LOG section, tap "Copy" → paste somewhere.
2. Server-side: app sends batched logs to backend; check `/api/logs` or wherever `RemoteLogger.shared` flushes to. See `ios/TeycanTranslate/Sources/Logger/RemoteLogger.swift:84` for the flush endpoint.
3. Real-time stream (requires Xcode):
   ```bash
   xcrun devicectl device process spawn-stream \
     --executable /usr/bin/log -- \
     stream --process TeycanTranslate --predicate 'eventMessage CONTAINS "bridge"'
   ```
   (Note: `--device` flag syntax differs across Xcode versions — adjust if needed.)

### Reproduce a typical realtime cycle

1. Open Bridge tab (default landing tab per DESIGN.md).
2. Verify language pair is `🇺🇦 UK ↔ 🇪🇸 ES` (or whatever is set).
3. Tap the round green mic at bottom.
4. First time only: grant microphone permission.
5. Speak Ukrainian: "Привіт, як справи сьогодні?" — pause 1s.
6. **Watch the conductor stage:**
   - Side A (UK) should highlight accent green + show "SPEAKING" state during your speech
   - Live caption below stage shows partial transcript (italic) while you speak
   - When you stop: Side A switches to "DONE ✓"
   - M's halo intensifies, three dots appear orbiting around M
   - Side B (ES) lights up + shows "HEARING" when translated audio starts playing through speaker
   - You hear "Hola, ¿cómo estás hoy?"
7. After M finishes speaking + `response.done(completed)` fires: conductor returns to `.idle`, a paired turn card appears in the archive below:
   ```
   UA → M → ES                   00:03 · 0.8s
   Привіт, як справи сьогодні?
   ──────────────
   Hola, ¿cómo estás hoy?                  ⎘
   ```
8. Repeat in Spanish to test mirrored flow.

---

## 9. Git state

Branch: `design/v1-editorial-strict-forest`

```bash
$ git status --short
 M .env.example                                       (pre-existing, unrelated)
 M DESIGN.md                                          (this change — V9 spec update)
 M ios/.../Features/Bridge/BridgeMessage.swift        (this change — createdAt field)
 M ios/.../Features/Bridge/BridgeSessionManager.swift (this change — CyclePhase + wiring)
 M ios/.../Features/Bridge/BridgeView.swift           (this change — V9 layout)
 M ios/.../TeycanTranslate.xcodeproj/...              (regenerated by xcodegen)
 M src/server.js                                      (pre-existing, unrelated)
?? ios/.../DesignSystem/Components/ConductorStage.swift    (NEW)
?? ios/.../DesignSystem/Components/DataFlow.swift          (NEW)
?? ios/.../DesignSystem/Components/EndpointPill.swift      (NEW)
?? ios/.../DesignSystem/Components/ProvenanceTrail.swift   (NEW)
?? docs/                                               (design exploration files, not iOS-related)
?? image.png                                          (pre-existing screenshot)
?? scripts/compare-transcripts.js                     (pre-existing tool)
?? scripts/gemini-transcribe.js                       (pre-existing tool)
?? scripts/soniox-transcribe.js                       (pre-existing tool)
```

**Nothing is committed.** Per project's git policy in `/Users/serbinov/.claude/CLAUDE.md`:

> Тобі ЗАБОРОНЕНО самостійно робити будь-які git-дії без явного прохання юзера.

User must explicitly approve commit. Suggested commit message when they do:

```
feat(bridge): V9 ConductorStage + ProvenanceTrail for realtime cycle

- Add CyclePhase state machine driving the 3-actor conductor stage
- Wire previously-unused output_audio_buffer.started event
- Pair user+assistant messages into single turn cards with provenance trail
- Per-turn latency tracking via lastSpeechStoppedAt → response.done
- 4 new components: ConductorStage, EndpointPill, DataFlow, ProvenanceTrail
- BridgeMessage gains createdAt for MM:SS timestamps in archive
- DESIGN.md updated with new Bridge spec

All 129 unit tests pass. Manual real-audio test reported bugs — see
docs/design/bridge-redesign/V9-HANDOFF.md for known issues.
```

---

## 10. How to roll back if needed

If V9 is broken beyond easy debugging, revert with:

```bash
# Discard ALL local changes (DESTRUCTIVE — confirm with user first)
git checkout HEAD -- ios/TeycanTranslate/Sources/Features/Bridge/
git checkout HEAD -- DESIGN.md
rm ios/TeycanTranslate/Sources/DesignSystem/Components/{ConductorStage,EndpointPill,DataFlow,ProvenanceTrail}.swift
cd ios/TeycanTranslate && xcodegen generate
```

This restores the pre-V9 layout (vertical-axis-removed haloed M centerpiece, alternating bubbles with arrow eyebrows). User had previously approved that as a baseline (commit `1671f69 design(tokens): replace palette with forest green / strict near-white`).

---

## 11. Critical files to read first (for the debugging agent)

In this order:

1. **`docs/design/bridge-redesign/FEASIBILITY.md`** — explains what was already in code before V9 (Soniox parallel STT, event parsing, etc.) so you know what NOT to re-build.
2. **`ios/TeycanTranslate/Sources/Features/Bridge/BridgeSessionManager.swift`** lines 1-110 (declarations + start/stop) and lines 342-470 (the entire `handle(event:)` switch — this is the heart of the realtime state machine, V9 added phase transitions here).
3. **`ios/TeycanTranslate/Sources/DesignSystem/Components/ConductorStage.swift`** — the new top-half layout. Phase → visual mapping is in the private helpers near the bottom.
4. **`ios/TeycanTranslate/Sources/Features/Bridge/BridgeView.swift`** lines 26-73 (the new body), lines 121-260 (the new `archiveStack` + `pairedTurnCard`).
5. **`docs/design/bridge-redesign/demos/v9-hybrid.html`** — open in browser. The auto-play cycle there is the ground truth for what each phase should look like. If the iOS app diverges from the demo, the demo is correct.

---

## 12. Open questions for the debugging agent

- Did the user grant microphone permission? Some bugs may simply be permission-denied.
- What's `BridgeSettings.useSoniox` value on the device? If `true`, Soniox path is in play and B3 (latency) + B4 (lang detection) are more likely. If `false`, only OpenAI `inputTranscriptDelta` is used.
- What does the in-app DIAG LOG show during a buggy session? The relevant lines start with `[rtc]` for events and `[stt]` for Soniox.
- Is `RemoteLogger` flushing? Check server `/api/logs` endpoint with the device's `publicDeviceID` (printed at app launch as `🚀 TeycanTranslate launched (deviceID=<8-char-hex>)`).
- Did the user's session reach `phase = .running`? If WebRTC handshake failed, all events below are moot.

---

## 13. Quick reference — what each component does at runtime

| Component | Renders when | Reads from | Writes to |
|---|---|---|---|
| `ConductorStage` | Always (top of Bridge tab) | `BridgeSessionManager.cyclePhase`, `BridgeSettings.langA/B`, last unfinalized message text | Lang sheet open callbacks |
| `EndpointPill` | Inside ConductorStage × 2 | `phase` (via `isActive` / `state` props) | onTap → opens `BridgeLangPickerSheet` |
| `DataFlow` | Inside ConductorStage × 2 | `isActive` (derived from phase) | — (pure animation) |
| `ProvenanceTrail` | Inside each archived turn card | `pair.user.createdAt`, `manager.sessionStartedAt`, `manager.latencyByItemID[pair.user.id]` | — |
| `CopyButton` | Inside each turn card next to translation | text | `UIPasteboard.general.string`, logs `[app] UI: copied translation` |
| `BridgeSessionManager` | App startup | `RealtimeEvent` stream from `RealtimeRTCClient`, `SonioxLiveSTT` token stream | `cyclePhase`, `messages[]`, `latencyByItemID`, etc. |

---

End of handoff. The debugging agent has everything needed to reproduce the bugs and triage. If anything is unclear or seems factually wrong about the code as it currently stands, treat the actual code (committed or local) as truth — this doc was written immediately after implementation and could drift.
