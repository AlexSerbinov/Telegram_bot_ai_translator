# Task: Soniox-based "Bridge"-style tab (working title)

**Status:** parked — pick up after Phrase TTS provider switch is shipped.

## What we want

A new tab that behaves *similarly* to the existing **Bridge** tab, but instead
of OpenAI's `gpt-realtime` doing STT + translation + TTS in one pipe, every
stage runs on Soniox + Groq:

```
mic  ─▶  Soniox STT (real-time)
              │  partial / final tokens, language tag
              ▼
         Groq translate  (openai/gpt-oss-120b, OpenAI-compatible)
              │  translated text
              ▼
         Soniox TTS (real-time, tts-rt-v1, Maya voice)
              │  PCM frames
              ▼
         iPhone speaker
```

User speaks Ukrainian → app detects it → translates to Spanish → speaks Spanish
back. Same conceptual flow as Bridge, but no OpenAI involvement.

## Why a separate tab

- Bridge is locked in on `gpt-realtime` (WebRTC + VAD + system-prompt-driven
  turn-taking). Replacing the pipeline in place would risk regressions.
- We want to A/B the two: latency, voice quality, cost, accuracy on
  Ukrainian / Spanish / English.
- Architecture is different enough (no WebRTC, no system prompt — just
  three serial WS streams) that sharing the existing view model would be
  awkward.

## Reuse audit (so we don't rebuild what's already there)

Code already in repo we can lean on:

| Capability                | File                                              | Notes |
|---------------------------|---------------------------------------------------|-------|
| Soniox real-time STT (WS) | `src/liveTranslator/sttSoniox.js` (server)        | Already used by Mini App `live.html` and Phrase tab. |
| Soniox real-time TTS (WS) | `src/liveTranslator/ttsSoniox.js` (server)        | Multi-stream WS, PCM s16le 24 kHz, serialized sub-streams. |
| Groq translation          | `src/services/groqService.js`                     | `openai/gpt-oss-120b` by default; OpenAI-compatible. |
| Server pipeline glue      | `src/liveTranslator/session.js`                   | The Mini App's `Live` tab already chains STT → translate → TTS. **Closest existing analog — start here.** |
| iOS PCM audio output      | needs a new component                             | Today we only play MP3/WAV via AVAudioPlayer; Soniox TTS streams PCM, so we'll either: (a) buffer to WAV per utterance, (b) feed AVAudioEngine with a PCM scheduler, (c) keep server-side WS proxy that wraps PCM into a streamable container. |
| iOS Soniox STT client     | `ios/.../STT/` + `ios/.../Features/Phrase/PhraseLiveSession.swift` | Phrase tab's `SonioxLiveSTT` already streams mic → Soniox WS → tokens. Reusable. |
| Bridge UI shell           | `ios/.../Features/Bridge/`                        | Layout, language pair selector, transcript stream, mic button — copy the structure, swap the engine. |

## Open questions to settle before coding

1. **Server vs direct client.** Phrase tab uses `/api/token` to mint a Soniox
   key and connects from the phone directly. Should the new tab do the same
   for both STT *and* TTS (two WS from iPhone), or proxy through our server
   like `liveTranslator/session.js` does for the Mini App? Direct = lower
   latency, but we'd need to expose the TTS key to the phone too.
2. **Turn-taking trigger.** Bridge uses `gpt-realtime` VAD. Soniox STT has
   `endpoint`/`final` events — is that enough, or do we add silence timeout?
3. **Language pair.** Bridge has explicit `langA / langB` + auto-direction
   prompt. For Soniox flow we still need to know "input is uk → speak es"
   (translation direction) — either user picks pair, or we detect with
   Soniox's per-token language tag and infer the other side.
4. **TTS playback on iPhone.** Cleanest path: buffer one utterance worth of
   PCM into WAV (like the new `/api/tts?provider=soniox` does), then play
   via AVAudioPlayer. Streaming PCM playback (AVAudioEngine) is more work
   and only worth it if we see noticeable lag.
5. **Cost / quotas.** Each turn is Soniox STT minutes + Soniox TTS chars +
   Groq tokens. Need a rough $/hour estimate before turning it on.

## Out of scope for v1

- Long-form session recording (Bridge has voice-log persistence; we'll add
  later if the tab proves useful).
- Speaker diarization in the transcript view.
- Choosing among Soniox voices (just hard-code Maya).
- iPad / macOS layout polish.

## Acceptance test (rough)

1. Open new tab. Pick "uk → es" language pair.
2. Tap mic, say "Привіт, як справи?" — STT partials should stream into a
   transcript bubble within ~300 ms of speaking.
3. Stop speaking (or hit stop). Within ~1.5 s the Spanish translation
   appears and a female Soniox voice (Maya) plays "Hola, ¿qué tal?".
4. Round-trip latency (mic-stop → first TTS byte) target: < 2 s.
5. No OpenAI calls in logs during the whole flow.

## Next concrete step

Spend an hour mapping `src/liveTranslator/session.js` against what an iOS
client would need, then decide question #1 (server-proxied vs direct). After
that the iOS tab is mostly UI work + glue.
