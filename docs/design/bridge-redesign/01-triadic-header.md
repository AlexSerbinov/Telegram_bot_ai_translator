# Variant 1 — Triadic Header + Provenance

## Mental model

**All three actors are visible at all times.** The screen opens with a "cast" row — UK person · M translator · ES person — locked at the top of the conversation stage. Every turn card below carries a tiny provenance trail in JetBrains Mono showing the translation path (`UA → M → ES` or `ES → M → UA`), making the translator's role *explicit on every turn*, not implicit.

Think of it as: "There are three people in this conversation, including the AI. Here's the cast. Here's what was said."

## Layout

```
┌──────────────────────────────────────────────┐
│ Bridge                          Live · 2:47  │  ← header (title + live indicator)
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│ TWO-WAY · UK ↔ ES · MEDIATOR                 │  ← eyebrow (JetBrains Mono)
│                                              │
│   ┌─────────┐    ╭───╮    ┌─────────┐        │
│   │ SIDE A  │    │ M │    │ SIDE B  │        │  ← cast row: 3 actor pills
│   │ 🇺🇦 UK ⌄ │    ╰───╯    │ 🇪🇸 ES ⌄ │        │     (tap UK/ES = language sheet,
│   └─────────┘             └─────────┘        │      M is non-interactive)
│                                              │
│   UA → M → ES                  02:47         │  ← provenance trail (mono, accent)
│   ┌────────────────────────────────────┐     │
│   │ Привіт, як справи сьогодні?        │     │  ← original (body-emphasis)
│   │ ──────────────                     │     │  ← hairline divider
│   │ Hola, ¿cómo estás hoy?             │     │  ← translation (body, muted)
│   └────────────────────────────────────┘     │
│                                              │
│                    ES → M → UA   02:53       │
│        ┌────────────────────────────────────┐│
│        │ Bien, gracias. ¿Y tú?              ││
│        │ ──────────────                     ││
│        │ Добре, дякую. А ти?                ││
│        └────────────────────────────────────┘│
│                                              │
│   UA → M → ES                  03:01         │
│   ┌────────────────────────────────────┐     │
│   │ Я хотів запитати про лікаря.       │     │
│   │ ──────────────                     │     │
│   │ Quería preguntar sobre el médico.  │     │
│   └────────────────────────────────────┘     │
│                                              │
│                                              │
│                  ╭─────╮                     │
│                  │  🎤  │                    │  ← round mic (64pt, accent fill)
│                  ╰─────╯                     │
│           SPEAKING · AUTO-DETECT             │
│              Tap mic to start                │
└──────────────────────────────────────────────┘
```

### Empty state

```
   ┌─────────┐    ╭───╮    ┌─────────┐
   │ 🇺🇦 UK   │    │ M │    │ 🇪🇸 ES   │
   └─────────┘    ╰───╯    └─────────┘

   Tap the mic. M will listen, detect the
   language, and translate to the other side.

                    🐾 (paw easter egg)
```

The cast row carries the explanatory weight — empty state copy becomes shorter and sits in clean negative space below it.

## Why it works

- **Translator visible from second one.** Even before any turn happens, the user sees there are three actors. No mystery.
- **Provenance trail is teachable.** First time a user sees `UA → M → ES`, they immediately understand: *my Ukrainian went through M and came out as Spanish*. Subsequent turns reinforce the mental model.
- **Lowest design-system drift.** Reuses existing `LangPill`, `ModelNode`, `EyebrowLabel`. The cast row is just an `HStack` of these three components.
- **Plays well with both empty and full states.** When the conversation grows, the cast row stays pinned at the top — like a Slack channel header.

## What it sacrifices

- **Vertical real estate.** Cast row eats ~60pt at the top. Less room for conversation history on a single screen.
- **Redundancy with eyebrow.** `TWO-WAY · UK ↔ ES · MEDIATOR` eyebrow + cast row says similar things. Either drop the eyebrow or keep both for emphasis (taste call).
- **M node looks symmetric but is non-interactive.** Users may try to tap it expecting a model picker. Either make it tappable (open model / prompt sheet — already exists for Bridge) or visually de-emphasize it (smaller, no chrome).

## Implementation sketch

**New components needed:**

```swift
// CastRow.swift — three actors locked at top
struct CastRow: View {
    let langA: Language
    let langB: Language
    var onTapA: () -> Void
    var onTapB: () -> Void
    var onTapM: () -> Void  // opens prompt-editor sheet

    var body: some View {
        HStack(spacing: DS.Space.md) {
            LangPill(eyebrow: "Side A", flag: langA.flag, code: langA.code, action: onTapA)
            ModelNode(isActive: false).onTapGesture(perform: onTapM)
            LangPill(eyebrow: "Side B", flag: langB.flag, code: langB.code, action: onTapB)
        }
    }
}

// ProvenanceTrail.swift — "UA → M → ES" line above each turn card
struct ProvenanceTrail: View {
    let from: String
    let to: String
    let timestamp: String

    var body: some View {
        HStack {
            Text("\(from.uppercased()) → M → \(to.uppercased())")
                .font(DS.Font.eyebrow)
                .foregroundStyle(DS.Color.accent)
            Spacer()
            Text(timestamp)
                .font(DS.Font.mono)
                .foregroundStyle(DS.Color.textSubtle)
        }
    }
}
```

**Changes to `BridgeView.swift`:**

- Replace the current lang-pair selector (Side A pill / swap / Side B pill) with `CastRow`.
- Move the swap button to a secondary affordance (long-press the M node? icon in the screen header? — design TBD).
- Drop the standalone `ModelNode` from the conversation stage — it now lives in `CastRow`.
- Each `turnCard` gets a `ProvenanceTrail` header.
- Conversation stage no longer needs the haloed M centerpiece (halo moves to M in cast row, at smaller scale).

**Estimated LOC:** ~40 added, ~20 removed.

## DESIGN.md impact

- Update § Three Modes > Bridge layout structure: replace "vertical axis" + "model node at center" with "cast row at top + provenance trail per turn".
- Add `CastRow` and `ProvenanceTrail` to the Components section.
- Keep the `ModelNode` component, but document its dual role (centerpiece vs. cast-row member with smaller halo).
