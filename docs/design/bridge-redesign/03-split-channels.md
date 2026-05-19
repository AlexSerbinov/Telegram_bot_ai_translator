# Variant 3 — Split Channels (Stenographer View)

## Mental model

**The screen is divided into two channels: one per person.** UK owns the left column. ES owns the right column. Each speaker's utterances accumulate only in *their own* column, in *their own language* — so the left column is always pure UA text, the right is always pure ES text. Between them runs a slim "translator dock" with the M node and a live waveform when it's working.

Think of it as: "Two parallel transcripts being recorded simultaneously, with the translator visibly relaying between them." Closest real-world analogue: court stenographer, simultaneous-interpretation booth.

## Layout

```
┌──────────────────────────────────────────────┐
│ Bridge                          Live · 2:47  │
│                                              │
│  🇺🇦 UA SPEAKER         ║         🇪🇸 ES SPEAKER│
│  ──────────────         ║         ──────────────│
│                         ║                      │
│  ┌──────────────────┐   ║                      │
│  │ Привіт, як       │   ║                      │
│  │ справи сьогодні? │   ║                      │
│  │ ··               │   ║                      │
│  │ Hola, ¿cómo      │   ║                      │
│  │ estás hoy?       │   ║                      │
│  └──────────────────┘   ║                      │
│                         ║                      │
│                         ║   ┌──────────────────┐│
│                         ║   │ Bien, gracias.   ││
│                         ║   │ ¿Y tú?           ││
│                         ║   │ ··               ││
│                         ║   │ Добре, дякую.    ││
│                         ║   │ А ти?            ││
│                         ║   └──────────────────┘│
│                         ║                      │
│  ┌──────────────────┐   ║                      │
│  │ Я хотів запитати │   ║                      │
│  │ про лікаря.      │   ║                      │
│  │ ··               │   ║                      │
│  │ Quería preguntar │   ║                      │
│  │ sobre el médico. │   ║                      │
│  └──────────────────┘   ║                      │
│                         ║                      │
│  ──────────────── ╭───╮ ────────────────       │
│         M · gpt-4o│ M │ ≋ LIVE  · 0.6s        │
│                   ╰───╯                        │
│                                                │
│                  ╭─────╮                       │
│                  │  🎤  │                      │
│                  ╰─────╯                       │
└──────────────────────────────────────────────┘
```

Each card shows the speaker's original text in body-emphasis, a `··` micro-separator, and the translation below in muted body. So the *left column* shows "what UA said, plus what ES heard" — and the *right column* shows "what ES said, plus what UA heard". Each speaker reads their own column.

### Empty state

```
  🇺🇦 UA SPEAKER         ║         🇪🇸 ES SPEAKER
  ──────────────         ║         ──────────────
                         ║
                         ║
                         ║
        Tap the mic — M routes between sides.
                         ║
                         ║
  ──────────────── ╭───╮ ────────────────
                   │ M │
                   ╰───╯
```

## Why it works

- **Most ergonomically honest layout for the actual use case.** In a real Bridge session, two people physically face each other with the phone between them. Hand the phone to your conversation partner and they see *their column* face them — they don't have to mentally filter "which side am I" from an alternating chat.
- **Translator gets a permanent stage of its own.** The bottom dock is always present, always shows live state, and isn't trying to share space with chat bubbles. M finally has an unambiguous home.
- **Each person's history is uncluttered.** ES speaker can scroll their column and see only their own turns. Less cognitive load.
- **Print-ready transcript.** Export the screen and you have a clean two-column court-style transcript — useful for the high-stakes use cases in the DESIGN.md cohort (medical, legal, school).

## What it sacrifices

- **Biggest departure from current code.** Abandons the alternating chat metaphor entirely. Requires rebuilding `conversationStage` from scratch.
- **Card width gets tight.** Each column is ~45% of screen = ~175pt on a 390pt iPhone. Long sentences wrap a lot. May need to allow each card to expand horizontally (overflowing into the other column) when only one side is active, which complicates layout logic.
- **Temporal ordering is less obvious.** When you look at the screen, "what was said last?" requires scanning both columns. Two solutions: (a) timestamps on every card, or (b) keep a synchronized vertical scroll so a card at vertical position N is later than a card at position N-1 in *either* column. Both add complexity.
- **The vertical divider is a strong line right through the middle of the screen.** Risks the same problem we just removed from v3.1 (vertical hairline overlapping content). Mitigation: divider only appears when there's content on both sides — otherwise stage is "wide" until both columns have turns.

## Implementation sketch

**New components needed:**

```swift
// ChannelColumn.swift — one side's transcript
struct ChannelColumn: View {
    let speaker: Language
    let turns: [BridgeMessage]
    let alignment: HorizontalAlignment  // .leading or .trailing

    var body: some View {
        VStack(alignment: alignment, spacing: DS.Space.md) {
            HStack {
                if alignment == .trailing { Spacer() }
                Text("\(speaker.flag) \(speaker.code.uppercased()) SPEAKER")
                    .font(DS.Font.eyebrow)
                if alignment == .leading { Spacer() }
            }
            Divider().background(DS.Color.hairline)
            ForEach(turns) { turn in
                channelCard(turn).frame(maxWidth: .infinity, alignment: alignment.asAlignment)
            }
        }
    }
}

// TranslatorDock.swift — bottom strip with M + live waveform
struct TranslatorDock: View {
    let isLive: Bool
    let latencyMs: Int?
    let modelName: String  // e.g. "gpt-realtime"

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Rectangle().fill(DS.Color.hairline).frame(height: DS.Stroke.hairline)
            Text("M · \(modelName)").font(DS.Font.eyebrow)
            ModelNode(isActive: isLive)
            if isLive { Waveform() }
            Rectangle().fill(DS.Color.hairline).frame(height: DS.Stroke.hairline)
        }
    }
}
```

**Changes to `BridgeView.swift`:**

- Rewrite `conversationStage` as `HStack { ChannelColumn(A) + Divider + ChannelColumn(B) }` plus a `TranslatorDock` pinned at the bottom of the stage.
- Filter `vm.manager.messages` into two arrays based on detected language for each column.
- Empty state and live state both need new copy.

**Estimated LOC:** ~120 added, ~70 removed.

## DESIGN.md impact

- Major: rewrite § Three Modes > Bridge layout structure. The "alternating turn cards" rule changes to "two parallel channels".
- Add `ChannelColumn`, `TranslatorDock`, and `Waveform` to Components.
- May need a new spacing token for the inter-channel divider gutter.

## When to pick this

If Bridge is the **killer feature** (DESIGN.md calls it the default landing tab) and you want a layout that *no other translation app uses*. Most translators do alternating chat. None do parallel channels. This is the boldest design move.

## When NOT to pick this

If you're shipping under deadline. This is the highest-implementation-cost option in the set and the most likely to surface edge cases on small screens.
