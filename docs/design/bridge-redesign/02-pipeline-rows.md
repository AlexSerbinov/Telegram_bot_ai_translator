# Variant 2 — Pipeline Rows

## Mental model

**Each turn is a dataflow pipeline you can watch.** The conversation isn't bubbles bouncing left and right — it's a sequence of small Stripe-style horizontal flows: source bubble → M node → translated bubble. The arrow direction makes the *flow of meaning* visible: UA turns flow left-to-right (UK speaks, M translates, ES receives), ES turns flow right-to-left.

Think of it as: "Two people, one mediator, and you're watching the translation happen in transit."

## Layout

```
┌──────────────────────────────────────────────┐
│ Bridge                          Live · 2:47  │
│ TWO-WAY · UK ↔ ES                            │
│                                              │
│  ┌────────┐         ╭───╮         ┌────────┐ │
│  │ 🇺🇦 UA  │ ──────→ │ M │ ──────→ │ 🇪🇸 ES  │ │
│  │        │         ╰───╯         │        │ │
│  │ Привіт,│                       │ Hola,  │ │
│  │ як     │                       │ ¿qué   │ │
│  │ справи?│                       │ tal?   │ │
│  └────────┘                       └────────┘ │
│  02:47                                   0.8s│
│                                              │
│  ┌────────┐         ╭───╮         ┌────────┐ │
│  │ 🇺🇦 UA  │ ←────── │ M │ ←────── │ 🇪🇸 ES  │ │
│  │        │         ╰───╯         │        │ │
│  │ Добре, │                       │ Bien,  │ │
│  │ дякую. │                       │ gracias│ │
│  │        │                       │   .    │ │
│  └────────┘                       └────────┘ │
│  02:53                                   0.6s│
│                                              │
│  ┌────────┐         ╭───╮         ┌────────┐ │
│  │ 🇺🇦 UA  │ ──────→ │ M │ ··· →   │ 🇪🇸 ES  │ │
│  │        │  pulse  ╰───╯ live    │        │ │
│  │ Я хотів│                       │  ···   │ │
│  │ запита-│                       │        │ │
│  │ ти про │                       │ (translating)│
│  │ лікаря.│                       │        │ │
│  └────────┘                       └────────┘ │
│  03:01                              (live)   │
│                                              │
│                  ╭─────╮                     │
│                  │  🎤  │                    │
│                  ╰─────╯                     │
│           SPEAKING · AUTO-DETECT             │
└──────────────────────────────────────────────┘
```

### Empty state

```
  ┌────────┐         ╭───╮         ┌────────┐
  │ 🇺🇦 UA  │  · · ·  │ M │  · · ·  │ 🇪🇸 ES  │
  │ (empty)│         ╰───╯         │ (empty)│
  └────────┘                       └────────┘

         Speak UA or ES — M routes accordingly.
```

The pipeline shape is visible even when empty, so the user understands the metaphor before saying anything.

## Why it works

- **Most explicit 3-entity visualization in this set.** You literally see source → M → target on every turn. There's no possible confusion about what M does.
- **Direction is encoded geometrically.** UA turns flow →, ES turns flow ←. Color-blind users, accessibility tools, and skim-readers all benefit.
- **Live state has a natural home.** When M is actively translating, the arrow / M node pulse animation makes it obvious. The destination bubble can show `···` until done. (Companion-mode realtime feel without abandoning chat history.)
- **Latency metric (`0.8s`) fits naturally** in the corner of each row — Stripe-receipt aesthetic. Power users see translation speed; casual users ignore it.

## What it sacrifices

- **Text width is the big tradeoff.** Three columns on a 390pt iPhone screen leaves ~110pt per bubble. Long sentences wrap aggressively. Mitigation: dynamic ratios (60/12/28% widths so source and target get more room than M), or vertical pipeline on small screens.
- **More visually complex.** Two bubbles + a connector per turn = 3× the strokes per row vs. variant 1. Risks looking "engineering-diagram" rather than "conversation".
- **Right-aligned ES turns flip the arrow but not the layout.** Solving this cleanly: either always render UA-left-ES-right with bidirectional arrow, or mirror the whole row (which doubles layout complexity). The mockup chooses the first — arrow flips, columns stay.

## Implementation sketch

**New components needed:**

```swift
// PipelineRow.swift — one turn as a horizontal pipeline
struct PipelineRow: View {
    let sourceLang: Language
    let targetLang: Language
    let sourceText: String
    let targetText: String
    let direction: TranslationDirection  // .leftToRight or .rightToLeft
    let timestamp: String
    let latencyMs: Int?
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: DS.Space.xs) {
                bubble(lang: sourceLang, text: sourceText)
                    .frame(maxWidth: .infinity)
                connector(direction: direction, isLive: isLive)
                    .frame(width: 60)
                bubble(lang: targetLang, text: targetText)
                    .frame(maxWidth: .infinity)
            }
            HStack {
                Text(timestamp).font(DS.Font.mono).foregroundStyle(DS.Color.textSubtle)
                Spacer()
                if let ms = latencyMs {
                    Text("\(Double(ms) / 1000, specifier: "%.1f")s")
                        .font(DS.Font.mono).foregroundStyle(DS.Color.textSubtle)
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(lang: Language, text: String) -> some View { /* ... */ }

    @ViewBuilder
    private func connector(direction: TranslationDirection, isLive: Bool) -> some View {
        HStack(spacing: 2) {
            arrow(direction.start)
            ModelNode(isActive: isLive)
            arrow(direction.end)
        }
    }
}
```

**Changes to `BridgeView.swift`:**

- Replace the alternating `turnCard` HStack with `PipelineRow`.
- Conversation stage no longer needs the central ModelNode (it lives inside each PipelineRow).
- Lang-pair selector stays at top (or fold into header — taste call).

**Estimated LOC:** ~80 added, ~50 removed.

## DESIGN.md impact

- Update § Three Modes > Bridge layout structure: turn cards are now horizontal pipelines, not alternating bubbles.
- Add `PipelineRow` and arrow-glyph spec to Components.
- Note: ModelNode now appears per-row (small, 20pt) rather than once per screen — update its spec to support both sizes.

## When to pick this

If you want Bridge to feel like a **tool**, not a chat. The pipeline aesthetic borrows from Stripe / Linear / Retool, signals "this is technical, this is precise, you can see the machinery". Good for a Founder-tier user who wants to feel like they're operating professional equipment.

## When NOT to pick this

If you want Bridge to feel like a **conversation**, not a system. Pipelines de-emphasize the humans (they become "endpoints") and emphasize the data flow. For high-stakes emotional conversations (doctor visits, custody talks), this might read cold.
