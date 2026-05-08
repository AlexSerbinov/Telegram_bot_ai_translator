# Handoff: Apply DESIGN.md to Teycan Translate iOS App

**Audience:** AI agent (or developer) tasked with integrating the approved design system into the existing iOS SwiftUI codebase.

**Status of design:** APPROVED. Source of truth = `DESIGN.md` in repo root.

**Status of code:** Working iOS app with 5378 LoC Swift, 64 unit tests passing, Apple Sign In + WebRTC + cost guard already shipped. Inherits beige `#F5F0EB` palette + amber accent + tabs named Voice/Realtime/Chat from earlier Telegram Mini App port. **All of this is to be replaced** per DESIGN.md.

---

## Read these first (in order)

1. `/Users/serbinov/Desktop/projects/ai-translator/DESIGN.md` — full design system spec (the single source of truth for visuals)
2. `/Users/serbinov/Desktop/projects/ai-translator/CLAUDE.md` — project instructions (deploy, env, conventions). Now contains a "Design System" section pointing here.
3. `/Users/serbinov/Desktop/projects/ai-translator/docs/02-features.md` — what each mode does, business context
4. `/Users/serbinov/Desktop/projects/ai-translator/ios/README.md` — iOS scaffolding (xcodegen-generated project, `project.yml` is the source of truth for the .xcodeproj)

## Visual references (for "what does this look like")

Open these in a browser before coding — they show the intent at three iteration steps. **Treat as reference only**; if anything contradicts DESIGN.md, DESIGN.md wins.

- `~/.gstack/projects/AlexSerbinov-Telegram_bot_ai_translator/designs/design-system-20260509/01-preview-v1-warm-editorial.html` — initial warm-cream + Instrument Serif direction (REJECTED, archived)
- `~/.gstack/projects/AlexSerbinov-Telegram_bot_ai_translator/designs/design-system-20260509/02-preview-v2-strict-amber.html` — editorial-strict with amber accent (accent REJECTED, otherwise direction APPROVED — three mode-specific layouts here are correct)
- `~/.gstack/projects/AlexSerbinov-Telegram_bot_ai_translator/designs/design-system-20260509/03-accent-compare-A-B-C-D.html` — four accent options side-by-side. **Option D (Forest Green `#1F4A3A`) was chosen.**

---

## Hard constraints (do not break)

1. **Do not change business logic** — `CostGuard.swift`, `RealtimeRTCClient.swift`, `AuthService.swift`, `APIClient.swift`, `SonioxLiveSTT.swift`, `AudioRecorder.swift`, `PCMStreamRecorder.swift`, etc. Visual changes only.
2. **All 64 unit tests must pass** after your changes. If a test relies on a renamed type/file, update the test alongside (same PR), do not delete or skip it. Run:
   ```bash
   cd ios/TeycanTranslate && xcodegen generate && \
   xcodebuild test -scheme TeycanTranslate \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
     CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""
   ```
3. **Apple HIG compliance** — bottom tab bar stays native, system push transitions stay default, status bar / Dynamic Island untouched.
4. **xcodegen-driven project** — when adding files, update `ios/TeycanTranslate/project.yml` and re-run `xcodegen generate`. Do NOT hand-edit `TeycanTranslate.xcodeproj` (it is gitignored).
5. **No external font CDN at runtime** — JetBrains Mono is bundled via SwiftPM Resources (offline-first principle for medical/legal context).
6. **Backwards-compatible API contract** — backend `/api/realtime/session`, `/api/realtime-chat/session`, `/api/translate-auto`, `/api/tts`, `/api/voice/transcribe`, `/api/auth/apple`, `/api/user/me` are untouched. This is iOS UI only.

---

## Scope of work

### 1. Replace design tokens

#### `ios/TeycanTranslate/Sources/DesignSystem/Colors.swift` (existing — rewrite)

Drop the inherited beige `#F5F0EB` and any amber. Implement the full color token system from `DESIGN.md` § Color (light + dark variants). Use `Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? darkHex : lightHex })` or `Color(.dynamic(light: ..., dark: ...))` extension pattern.

Token names must match DESIGN.md (`bg.canvas`, `bg.surface`, `text.ink`, `accent.signature`, `accent.soft`, `accent.glow`, `hairline`, `hairline.strong`, `semantic.success`, `semantic.warning`, `semantic.error`, plus dark variants).

Expose as static `Color` properties on a `DS.Color` namespace (or `Theme.Color`) so call sites read `DS.Color.accent` not raw hex.

#### `ios/TeycanTranslate/Sources/DesignSystem/Typography.swift` (existing — rewrite)

Drop any serif. Use SF Pro (system) for everything except mono. Register **JetBrains Mono** as bundled resource:
- Add `JetBrainsMono-Regular.ttf`, `Medium.ttf`, `SemiBold.ttf` to `ios/TeycanTranslate/Resources/Fonts/`
- Update `project.yml` to include the fonts as resources
- Add `UIAppFonts` entries to `Info.plist`

Implement type roles per DESIGN.md § Typography (`displayXL`, `displayL`, `title`, `headline`, `body`, `bodyEmphasis`, `caption`, `eyebrow`, `mono`, `monoEmphasis`). Each role exposes a `Font` and the spec sheet (size, weight, tracking, lineHeight). Use SwiftUI `.tracking()` for letter-spacing and `.monospacedDigit()` for tabular nums.

#### `ios/TeycanTranslate/Sources/DesignSystem/Spacing.swift` (NEW)

4pt grid scale + radius scale per DESIGN.md § Spacing and § Layout. Static properties on `DS.Space` and `DS.Radius`.

```swift
public enum DS {
    public enum Space {
        public static let space2xs: CGFloat = 2
        public static let xs: CGFloat = 4
        // ... per DESIGN.md
    }
    public enum Radius {
        public static let sm: CGFloat = 4
        public static let md: CGFloat = 6
        public static let lg: CGFloat = 8
        public static let full: CGFloat = 9999
    }
}
```

#### `ios/TeycanTranslate/Sources/DesignSystem/Motion.swift` (NEW)

Animation specs per DESIGN.md § Motion. Static `Animation` values:
- `.micTap` = `.easeOut(duration: 0.15)`
- `.bridgeTurn` = `.easeOut(duration: 0.2)` with `.transition(.move(edge: .top).combined(with: .opacity))`
- `.companionLine` = `.easeOut(duration: 0.18)` with `.transition(.opacity.combined(with: .offset(y: 8)))`
- `.livePulse` = repeating linear 1.6s, opacity 1 → 0.45 → 1
- `.tabChange` = `.easeOut(duration: 0.1)` opacity crossfade
- `.banner` = `.easeOut(duration: 0.25)` slide from top

### 2. Rename tabs (UI labels and code)

**Mapping:**

| Old (code + UI) | New (UI label) | New (code path) |
|---|---|---|
| Voice | **Phrase** | `Sources/Features/Phrase/` |
| Realtime | **Companion** | `Sources/Features/Companion/` |
| Chat | **Bridge** | `Sources/Features/Bridge/` |

Two-step approach to keep tests green:
1. Move folders + rename Swift types (`VoiceView` → `PhraseView`, `RealtimeViewModel` → `CompanionViewModel`, `ChatSessionManager` → `BridgeSessionManager`, etc).
2. Update all import sites (search `Voice`, `Realtime`, `Chat` token usage scoped to feature folders) and update `project.yml` source paths.
3. Run `xcodegen generate` and tests after each module rename.

Update visible labels:
- `MainTabView.swift` tab labels: "Phrase" / "Companion" / "Bridge"
- Tab icons: use mono geometric chars or SF Symbols closest to those — Phrase = `═` or `text.alignleft`, Companion = `≋` or `waveform`, Bridge = `⇆` or `arrow.left.arrow.right`
- Screen titles in each view: "Phrase" / "Companion" / "Bridge" with subtitles per DESIGN.md § Three Modes
- App-level naming `TeycanTranslateApp.swift` is fine to leave

Test files that reference old names (`VoiceLanguagesTests`, `ChatSettingsTests`, etc) — rename to match new module names AND keep tests passing.

### 3. Apply mode-specific layouts

Each tab has its own structure — they are NOT three views of the same shell. Build each per DESIGN.md § Three Modes.

#### Phrase (formerly Voice)

- Top: language pair selector (From pill / `⇄` / To pill). Existing logic in `VoiceViewModel` for language swap stays.
- Middle: output card (`DS.Radius.lg`, surface bg, eyebrow `ORIGINAL · UK · 15 WORDS`, original text, hairline, translation muted, action row Speak/Copy/Retry)
- Bottom: **square** mic button 64×64 (`DS.Radius.sm`), accent fill, label `TAP TO SPEAK`. **Replace existing round mic.**
- Live debounced TTS / Soniox WS pipeline stays — only swap the visual.

#### Companion (formerly Realtime)

- Top: AirPods status bar (16pt margin, `DS.Radius.md`, surface bg)
  - Detect connected route via `AVAudioSession.sharedInstance().currentRoute.outputs` — check `portType == .bluetoothA2DP` || `.headphones` || `.bluetoothLE`
  - States: `CONNECTED · ROUTING AUDIO` (success green) / `NOT CONNECTED · TAP TO CONNECT` (warning, opens Bluetooth settings)
- **Headphones gate:** if user taps Start with no headphones, present a full-screen overlay (96% opacity surface, blur backdrop):
  - Headphones icon 40pt
  - Title "Connect headphones to start"
  - Body explaining audio feedback / privacy reasoning
  - CTA "Open Bluetooth Settings" → `UIApplication.shared.open(URL(string: "App-Prefs:Bluetooth")!)` (or `App-Prefs:` root if Bluetooth deep-link blocked)
- Target language picker (replaces current target pill — now first-class). Card with eyebrow `→ TARGET LANGUAGE` and chevron, opens `Sheet` with language list. Use existing `TargetLanguages.swift` enum.
- Live transcript stream — single column, original lines (mono italic 11pt subtle) + translated lines (body 13pt ink, with 2pt forest left border via `.overlay(Rectangle().frame(width: 2).foregroundColor(DS.Color.accent), alignment: .leading)`)
- Live caret blink on the actively-streaming line (`▎` mono char with opacity blink)
- Bottom: **square** mic button 64×64 (`DS.Radius.sm`), label `STOP LISTENING` / `START LISTENING`

#### Bridge (formerly Chat)

- Top: **NEW** — language pair selector identical to Phrase (A pill / `⇄` / B pill). Was implicit in old Chat tab; must be explicit so model knows which two languages to mediate.
- Conversation stage: ZStack with
  - `Rectangle().frame(width: 1).foregroundColor(DS.Color.hairline)` centered vertically (the axis)
  - `ModelNode` at vertical center — 28pt circle, 1pt accent border, surface bg, `M` letter (JetBrains Mono Semibold accent)
  - `LazyVStack` of turn cards alternating sides via padding (`right` turn = `.trailing` align with 50pt leading padding so it doesn't overlap node; `left` turn = `.leading` with 50pt trailing padding)
  - Each turn: eyebrow `UA → ` or ` ← ES` with accent on language code, original (body-emphasis 12pt), dashed hairline, translation (body 11pt muted)
- Bottom: **round** mic button 64pt full circle (`DS.Radius.full`), label `SPEAKING · auto-detect`. **Different shape from Phrase/Companion** — round encodes 2-way symmetric conversation.

### 4. Update component library

Refactor `ios/TeycanTranslate/Sources/DesignSystem/Components/` to be feature-agnostic and reusable. New components:

- `MicButton.swift` (rewrite) — accept `shape: MicShape { case round, square }`, size, accent color binding, isActive state
- `LiveIndicator.swift` (NEW) — accent dot + tabular `Live · MM:SS`, infinite blink animation
- `LangPill.swift` (NEW) — eyebrow + value, tap presents language picker sheet, 4pt corner
- `EyebrowLabel.swift` (NEW) — JetBrains Mono 11pt UPPER 0.18em, optional leading em-dash, optional accent color override
- `ModelNode.swift` (NEW, used in Bridge) — 28pt circle, accent border, `M` letter, optional pulse on active turn
- `DeadlineBanner.swift` (existing — restyle) — DESIGN.md § Components > Cost Guard Banner specs
- `LogPanel.swift` (existing — restyle to strict aesthetic, mono font for log entries)

### 5. Brand mark + onboarding

- App icon: clean wordmark `T` monogram or `Teycan` lowercase in SF Pro Display Bold, ink on cream. NO cartoon. NO color background.
- Onboarding screen 2 (existing or new): dog Teycan origin story per DESIGN.md § Brand Mark
- About screen (Settings → About): full origin story
- Empty states (e.g., when conversation is empty): paw-print SF Symbol or custom `pawprint.fill` at 12% opacity in accent color, anchored bottom-trailing of conversation area

---

## Verification checklist

After all changes:

- [ ] `xcodegen generate` succeeds without warnings
- [ ] `xcodebuild test ...` passes 64/64 (or 64+N if you added new tests)
- [ ] Light mode: each tab matches DESIGN.md screenshots in `~/.gstack/projects/.../designs/design-system-20260509/02-preview-v2-strict-amber.html` STRUCTURALLY (replace amber with forest green when comparing)
- [ ] Dark mode: legible, accent forest green lifted to `#3D8A6A`, surfaces are `#0A0A0A` / `#161616` / `#1F1F1F` per spec
- [ ] AirPods gate works: airplane mode + Bluetooth off → tap Start in Companion → blocker appears
- [ ] Bridge model node visible in middle of conversation, axis hairline visible, turns don't overlap node
- [ ] Phrase has square mic, Companion has square mic, Bridge has round mic
- [ ] Tab bar shows "Phrase / Companion / Bridge" with mono icons
- [ ] No reference to "Voice", "Realtime", "Chat" remains as user-facing label (code-internal references being phased out are acceptable mid-migration but commit-final)
- [ ] No reference to amber `#B8541A` or beige `#F5F0EB` in `Sources/`

---

## Delivery

- Branch name: `design/v1-editorial-strict-forest`
- Commits: small atomic — "tokens: replace Colors.swift with DESIGN.md palette", "rename: Voice → Phrase", "feat(Companion): add headphones gate", etc.
- PR title: "Apply DESIGN.md v1: Editorial-Strict + Forest Green + Phrase/Companion/Bridge"
- PR body: brief table of files changed, per-tab before/after screenshot pairs (light + dark), test result `64/64 passing`, list of any deferred items
- Do NOT auto-merge. Request review from `oleksandr@techchain.solutions` (the user).

If you hit blockers (missing fonts file, AirPods detection edge case, font registration not picking up, anything ambiguous in DESIGN.md), STOP and post a question with the specific file:line and what you tried. Do not guess on visual decisions — DESIGN.md decisions log is the precedent for what's locked.

---

## Out of scope (later phases)

These come AFTER design integration is shipped — do not include in this PR:
- App Store assets (icon 1024×1024, screenshots, app preview video)
- Privacy Policy / Terms of Service
- StoreKit 2 IAP integration ($15/mo subscription)
- Apple Watch companion
- Localizable.xcstrings full UA/EN/ES translation
- Lock-screen control (`MPRemoteCommandCenter`)
