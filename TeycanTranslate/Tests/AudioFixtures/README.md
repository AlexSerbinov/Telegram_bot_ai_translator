# Audio Fixtures — Voice Translator QA

Pre-recorded voice samples for automated testing of TeycanTranslate's voice flow. Routed into iOS Simulator via BlackHole. Full procedure in [`../../../CLAUDE.md`](../../../CLAUDE.md) → "Audio Testing — Voice Translator QA".

## Current fixtures

| File | Language | Content (gist) | Size | Notes |
|------|----------|----------------|------|-------|
| `hello-uk.wav` | UK | Weather in Kyiv — medium sentence | 614 KB | Cyrillic, colon-separated clauses |
| `hello-ru.wav` | RU | Loves Ukrainian borscht — with filler "э-э" | 640 KB | Tests RU vs UK detection (easy to confuse) |
| `hello-es.wav` | ES | "¿quieres un té o un café con azúcar?" | 255 KB | Inverted ?, accented chars |

Format: PCM `.wav` (recorded via VoiceInk on macOS).

Exact transcriptions + expected translations for each fixture are in [`expected.json`](./expected.json). Agent validates real STT/translation output against these.

## How fixtures were recorded

Dictated through [VoiceInk](https://github.com/prakashjoshi/VoiceInk) (macOS dictation app). Source `.wav` files live at:
`~/Library/Application Support/com.prakashjoshipax.VoiceInk/Recordings/<UUID>.wav`

## Adding new fixtures

1. Record via VoiceInk (or any tool that produces wav/m4a/mp3).
2. Drop file here with descriptive name: `<scenario>-<lang>.<ext>`. Examples: `noisy-uk.wav`, `long-es.m4a`, `numbers-en.wav`.
3. Add entry to `expected.json` with `detectedLanguage`, `transcribed`, and 2+ target-language translations.
4. Commit and push to the iOS repo.
5. Run "test voice flow" — agent will validate the new fixture end-to-end.
