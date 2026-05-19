# Test Plan — DESIGN.md v1 Integration

**Branch:** `design/v1-editorial-strict-forest`
**Date:** 2026-05-09

## Goals
1. Confirm 64 (or 64+N) unit tests still pass after design refactor.
2. Confirm app builds for iPhone 17 Pro simulator with no errors / no warnings.
3. Visually verify each tab matches DESIGN.md structurally in Light + Dark mode.
4. Verify mode-specific behaviors (AirPods gate, cost-guard banner, tab-switch hardstop).
5. Verify font registration (JetBrains Mono used in eyebrows + mono labels).

## Static checks

| # | Check | Pass criterion |
|---|---|---|
| S1 | `grep -r "F5F0EB"` in `Sources/` | 0 hits (old beige removed) |
| S2 | `grep -r "B8541A"` in `Sources/` | 0 hits (old amber removed) |
| S3 | `grep -rE "VoiceView\|RealtimeView\|ChatView" Sources Tests` | 0 hits — types fully renamed |
| S4 | `grep -rEn "MicButton\(" Sources` | All call sites use new API: `MicButton(shape:, isActive:, ...)` |

## Build + tests

| # | Check | Command | Pass |
|---|---|---|---|
| B1 | xcodegen succeeds | `xcodegen generate` | "Created project at ..." |
| B2 | Debug build | `xcodebuild ... build` | `** BUILD SUCCEEDED **` |
| B3 | Unit tests | `xcodebuild test ...` | `Executed 114 tests, 0 failures` |
| B4 | Fonts bundled | `find build -name 'JetBrainsMono-*.ttf'` | All three TTF present in `.app/Contents/Resources` |

## Visual smoke (per tab)

For each tab in `[phrase, companion, bridge]`:
- launch app with `-bypass-auth 1 -start-tab <tab>`
- screenshot
- confirm structural elements per DESIGN.md.

| # | Tab | What to verify |
|---|---|---|
| V-P-1 | Phrase | Header "Phrase" in SF Pro Display, eyebrow "ONE-SHOT · TAP, SPEAK, DONE" with leading em-dash, From/To `LangPill` row, output card with 8pt corners, square mic at bottom |
| V-P-2 | Phrase | After bypass: log entries visible, no "Voice" string anywhere |
| V-C-1 | Companion | Header "Companion", AirPods row, Target language card, "Stream" panel, square mic |
| V-C-2 | Companion | Empty state placeholder text uses `text.subtle` color (light grey) |
| V-B-1 | Bridge | Header "Bridge", Side A / ⇄ / Side B pills, vertical axis hairline visible, ModelNode "M" centered, ROUND mic at bottom |
| V-B-2 | Bridge | Empty state has paw-print at 12% opacity bottom-right corner |

## Dark mode

Toggle simulator appearance: `xcrun simctl ui booted appearance dark`.
Repeat the per-tab checks in dark mode.

| # | Check |
|---|---|
| D1 | Backgrounds become `#0A0A0A`, surfaces `#161616` |
| D2 | Forest green lifts to `#3D8A6A` (more luminance) |
| D3 | Text legible — primary white `#FAFAFA`, muted grey `#A3A3A3` |
| D4 | Eyebrow labels still readable — JetBrains Mono renders |

## Functional

| # | Test | Steps | Expected |
|---|---|---|---|
| F1 | Tab-switch hardstop | Start Companion session → tab to Bridge | Companion session terminates (`[guard] hardStop(tabSwitch)`) |
| F2 | Phrase mic record | Tap mic on Phrase → speak → Stop | sourceText populated, translation appears, `[stt] soniox audio #N sent` in log |
| F3 | Bridge round mic | Bridge tab — mic button is circular, `mic.fill` glyph centered | visual check |
| F4 | Cost-guard warn (mocked) | n/a — covered by unit tests `CostGuardTests.test_warn_firesBeforeDeadline` | green |
| F5 | AirPods gate | Companion tab → tap mic without headphones | full-screen gate appears with "Connect headphones" message |

## Out of scope (deferred)

- Real Apple Sign In flow (requires paid Apple Developer Team — DEBUG bypass used).
- Live OpenAI WebRTC end-to-end (requires real network + valid OPENAI_API_KEY — manual user check on device).
- App Store screenshots / icon final.
- Localized strings UA/EN/ES.
