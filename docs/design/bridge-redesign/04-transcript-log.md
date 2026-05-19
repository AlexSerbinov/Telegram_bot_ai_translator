# Variant 4 — Transcript Log (Linear-style)

## Mental model

**It's not a chat. It's a transcript.** Each turn is one rectangular block running edge-to-edge: speaker header (flag + label + timestamp), original utterance in body-emphasis, an inline `↘ via M` chip showing the translator did its job, and the translation below in muted body. No bubbles, no alternating left/right — pure top-to-bottom log, like Linear comments, Granola notes, or a podcast transcript.

Think of it as: "This is a record of a real conversation that happened. Read it like minutes from a meeting."

## Layout

```
┌──────────────────────────────────────────────┐
│ Bridge                          Live · 2:47  │
│ TWO-WAY · UK ↔ ES · VIA M                    │
│                                              │
│ ──────────────────────────────────────────── │
│ 🇺🇦 UA SPEAKER · 02:47                        │
│                                              │
│ Привіт, як справи сьогодні?                  │
│                                              │
│   ↘ via M · gpt-realtime · 0.8s              │
│                                              │
│ Hola, ¿cómo estás hoy?                       │
│ ──────────────────────────────────────────── │
│                                              │
│ 🇪🇸 ES SPEAKER · 02:53                        │
│                                              │
│ Bien, gracias. ¿Y tú?                        │
│                                              │
│   ↘ via M · gpt-realtime · 0.6s              │
│                                              │
│ Добре, дякую. А ти?                          │
│ ──────────────────────────────────────────── │
│                                              │
│ 🇺🇦 UA SPEAKER · 03:01                        │
│                                              │
│ Я хотів запитати про лікаря — чи можна       │
│ записатися на прийом наступного тижня?       │
│                                              │
│   ↘ via M · gpt-realtime · (translating)     │
│                                              │
│ ···                                          │
│ ──────────────────────────────────────────── │
│                                              │
│                  ╭─────╮                     │
│                  │  🎤  │                    │
│                  ╰─────╯                     │
│           SPEAKING · AUTO-DETECT             │
└──────────────────────────────────────────────┘
```

Each block is bounded above and below by a hairline divider (not a card border) — the dividers form the rhythm of the log. No background fill, no rounded corners. The full screen width belongs to each turn, so long sentences breathe.

### Empty state

```
 TWO-WAY · UK ↔ ES · VIA M

 ──────────────────────────

 Tap the mic. Each turn becomes a record:
   speaker, original text, ↘ via M, translation.

 ──────────────────────────

                  🐾
```

## Why it works

- **Highest information density in the set.** No padding wasted on bubble chrome, no alternating gutters, no separate columns. On a 6.7" iPhone, you fit ~4 full turns on screen vs. ~2.5 with bubbles.
- **`↘ via M` is the smartest provenance signal of all four variants.** It's an *inline editorial mark*, the way a translator's note appears in a published book ("translated by ___ from the original Russian"). The translator is acknowledged but doesn't take center stage. Quietly authoritative.
- **Matches DESIGN.md tone exactly.** Editorial-Strict, sans-only, hairline-as-structure. Reads like Linear's "comments on an issue" or Granola's meeting notes. The DESIGN.md says "Linear, Granola, Things 3, Stripe" are the references — this is the variant that's most directly inspired by them.
- **Print-ready, share-ready, screenshot-ready.** Long-press → "Share transcript" produces a clean export. Useful for the legal / medical use cases (you can hand the transcript to a doctor or notary).
- **Live state is graceful.** While M is translating, the turn shows `···` in the translation slot. When it completes, the text replaces the dots. No layout shift, no card appearing-and-disappearing.

## What it sacrifices

- **No spatial separation between UA and ES turns.** You have to read each speaker header to know who said what. Mitigation: speaker flag is the leftmost element of each block and uses color (UA = blue/yellow bar accent, ES = red/yellow bar accent — but the project palette is monochrome + forest green, so this would need careful handling, probably just the flag emoji + bold uppercase code is enough).
- **Loses the "chat" feeling that some users expect from translation apps.** Most consumer translators use bubbles because users have been trained by iMessage. This is a deliberate "we're not iMessage, we're something more serious" move — aligned with the DESIGN.md anti-references (Duolingo, Google Translate, iTranslate).
- **Translator becomes a metadata chip, not an actor.** "↘ via M" is so subtle that some users may not notice the AI is in the loop at all. If brand strategy wants M to be a prominent character ("Teycan AI translates between you and them"), this variant under-sells it.

## Implementation sketch

**New components needed:**

```swift
// TranscriptBlock.swift — one turn as a full-width log entry
struct TranscriptBlock: View {
    let speaker: Language
    let timestamp: String
    let originalText: String
    let translatedText: String?  // nil while translating
    let latencyMs: Int?
    let modelName: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            // Speaker header
            HStack(spacing: DS.Space.xs) {
                Text(speaker.flag)
                Text("\(speaker.code.uppercased()) SPEAKER · \(timestamp)")
                    .font(DS.Font.eyebrow)
                    .foregroundStyle(DS.Color.textMuted)
            }

            // Original
            Text(originalText)
                .font(DS.Font.bodyEmphasis)
                .foregroundStyle(DS.Color.textInk)

            // Provenance chip
            HStack(spacing: 6) {
                Text("↘ via M · \(modelName)")
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.accent)
                if let ms = latencyMs {
                    Text("· \(Double(ms) / 1000, specifier: "%.1f")s")
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.textSubtle)
                } else {
                    Text("· translating…")
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.textSubtle)
                }
            }
            .padding(.leading, DS.Space.md)

            // Translation
            Text(translatedText ?? "···")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textMuted)
        }
        .padding(.vertical, DS.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Color.hairline).frame(height: DS.Stroke.hairline)
        }
    }
}
```

**Changes to `BridgeView.swift`:**

- Replace `turnCard(_:settings:)` with `TranscriptBlock(...)`.
- Drop the central `ModelNode` and its halo — M now lives only as text in the `↘ via M` chip.
- Lang-pair selector at top remains (becomes simpler — no spatial alternation to anchor).
- Conversation stage becomes a plain `VStack` of `TranscriptBlock`s with no central axis.

**Estimated LOC:** ~50 added, ~60 removed (net -10 — the simplest implementation).

## DESIGN.md impact

- Update § Three Modes > Bridge layout structure: replace "alternating turn cards" with "edge-to-edge transcript blocks".
- Remove `ModelNode` from Bridge spec (still used in Companion-mode realtime indicator, so the component stays).
- Add `TranscriptBlock` and the `↘ via M` provenance-chip pattern to Components.
- Add a note: this is the rule for Bridge; Phrase and Companion keep their own structures.

## When to pick this

If you want Bridge to feel like a **serious tool** — minutes of a meeting, transcript of a deposition, record of a doctor's visit. The Founder-edition cohort (Ukrainian IT pros in Spain/Portugal, high-stakes conversations) is exactly the audience for "transcript that becomes a document" thinking. Most aligned with DESIGN.md's stated peers (Linear, Granola).

## When NOT to pick this

If brand strategy wants M to be a visible *character* (mascot-adjacent, "Teycan helps you talk"). This variant treats M like a copyright notice on a translation, not like a third actor at the table.

## Hybrid worth considering

**Variant 4 body + Variant 1 cast row.** Top of screen: 3-actor cast row (UK / M / ES). Body: transcript log. This is probably the strongest combination — keeps M visible as an actor at the top, but the body stays editorial and dense. Mention as a candidate when you reply.
