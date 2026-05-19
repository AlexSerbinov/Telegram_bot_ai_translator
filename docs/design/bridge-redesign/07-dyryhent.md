# Варіант 7 — Диригент (M як центральний персонаж)

## Ментальна модель

**Перекладач — це головний герой, а двоє людей — endpoints.** На відміну від усіх попередніх варіантів де M — це маленький символ, тут M — велике центральне коло (80pt) у центрі екрану. Зліва і справа від нього — два "endpoint" блоки: 🇺🇦 UA endpoint і 🇪🇸 ES endpoint, з'єднані з M короткими лініями. Коли UA говорить — ліва лінія "тече" від UA до M (animated dots). Коли M генерує — саме M пульсує/обертається. Коли M говорить ES — права лінія тече від M до ES.

Думай про це так: "Я не дивлюся на чат. Я дивлюся на диригента що перекладає між двома сторонами. М — це Teycan AI у його чистому вигляді."

## Розкладка

```
┌──────────────────────────────────────────────┐
│ Bridge                          Live · 2:47  │
│                                              │
│  ╭──────────────────────────────────────╮   │
│  │                                       │  │
│  │   🇺🇦         ╭───────╮         🇪🇸     │  │
│  │  ┌────┐       │       │       ┌────┐   │  │
│  │  │ UA │ ····→ │   M   │ ····→ │ ES │  │  │ ← диригент-сцена
│  │  │    │       │       │       │    │  │  │
│  │  └────┘       │ ◐ ◐ ◐ │       └────┘  │  │
│  │ listening     ╰───────╯        idle    │  │
│  │               thinking                 │  │
│  │                                       │  │
│  │  "Привіт, як справи сьогодні..."      │  │ ← live UA caption
│  │  (caption з'являється у залежності    │  │
│  │   від поточного спікера — позиція     │  │
│  │   завжди під M)                       │  │
│  ╰──────────────────────────────────────╯   │
│                                              │
│ ─────────── ARCHIVE ────────────             │
│                                              │
│ 02:47   Привіт, як справи?                   │
│         → Hola, ¿qué tal?            0.8s    │
│                                              │
│ 02:53   Bien, gracias. ¿Y tú?                │
│         → Добре, дякую. А ти?         0.6s    │
│                                              │
│                                              │
│                  ╭─────╮                     │
│                  │  🎤  │                    │
│                  ╰─────╯                     │
│           SPEAKING · AUTO-DETECT             │
└──────────────────────────────────────────────┘
```

### Фази диригента

```
IDLE
   UA ────── M ────── ES
   idle    ready      idle

UA SPEAKING (потік ліворуч → центр)
   UA ··→ M       ES
   live   listen  idle

M TRANSLATING (центр обертається, обидві лінії тихі)
   UA          M         ES
   done    ◐ ◐ ◐ ◐       waiting
                spin

M SPEAKING TO ES (потік центр → праворуч)
   UA       M ··→ ES
   done    out    live·🔊

ES SPEAKING (потік праворуч → центр)
   UA       M ←·· ES
   idle    listen  live
```

## Чому це працює

- **Найбільший brand statement.** M стає видимим центром продукту. Teycan AI — не "невидимий помічник", а живий суб'єкт. Це найбільш узгоджено з ім'ям ("Teycan" = собака founder-а, M = the dog який живе у застосунку).
- **Найбільш intuitively-physical metaphor.** Двоє людей розмовляють через перекладача. Текст потоку (data dots) — це їх слова що "летять" через M. Це візуальна метафора яка не потребує пояснення.
- **Найбільш cinematic.** Якщо колись робиш marketing video чи App Store screenshot — Disrupt-стиль "watch the AI work" — це той варіант. Інші варіанти показують переклад як список повідомлень; цей показує його як машинерію.
- **Archive все ще є знизу, але мінімальний.** Бо центральна увага — на сцені. Archive — для скрол-перегляду коли треба згадати "що було сказано 2 хвилини тому".

## Що жертвується

- **Найбільше відхилення від поточної кодової бази.** Жоден існуючий компонент не підходить — треба будувати з нуля `ConductorStage`, `EndpointBlock`, `DataFlow` (animated dots), `WhirlingM`. Це ~200+ LOC.
- **Animation budget великий.** Animated dots, M whirling, captions appearing/fading — все має бути 60fps на iPhone 12+. Не складно у SwiftUI з TimelineView + Canvas, але треба тестувати на target hardware.
- **Може здатися "too playful" для серйозного use-case.** DESIGN.md явно anti-Duolingo. Animated dots + whirling M трохи близько до cartoon. Mitigation: extremely restrained palette (monochrome dots, just accent on M), коротка тривалість анімацій (200ms transitions, не "magical" 800ms ones).
- **Long-form text не вміщається у caption box.** Якщо хтось говорить 2-3 речення підряд, caption розростається. Треба ellipsis / scroll within caption. Або обмежити caption останніми ~100 символами і показувати "..." prefix.

## Implementation sketch

```swift
// ConductorStage.swift — центральний "театр"
struct ConductorStage: View {
    let leftLang: Language
    let rightLang: Language
    let phase: BridgeCyclePhase   // .idle / .leftSpeaking / .translating / .rightHearing / .rightSpeaking / .leftHearing
    let liveCaption: String?
    let captionLang: Language?

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.md) {
                EndpointBlock(lang: leftLang, isLive: phase.isLeftActive)
                DataFlow(direction: phase.leftFlowDirection, active: phase.isLeftFlowing)
                    .frame(width: 32, height: 24)
                ConductorNode(phase: phase)
                DataFlow(direction: phase.rightFlowDirection, active: phase.isRightFlowing)
                    .frame(width: 32, height: 24)
                EndpointBlock(lang: rightLang, isLive: phase.isRightActive)
            }
            if let caption = liveCaption, let lang = captionLang {
                Text(caption)
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(captionColor(for: lang))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, DS.Space.md)
                    .transition(.opacity)
            }
        }
        .padding(DS.Space.lg)
        .background(DS.Color.bgSurface.opacity(0.4))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
        )
    }
}

// ConductorNode.swift — центральне М з phase-залежним станом
struct ConductorNode: View {
    let phase: BridgeCyclePhase
    @State private var spinAngle: Double = 0

    var body: some View {
        ZStack {
            Circle().fill(DS.Color.accentGlow).frame(width: 100, height: 100).blur(radius: 14)
            Circle().fill(DS.Color.bgSurface).frame(width: 80, height: 80)
            Circle().strokeBorder(DS.Color.accent, lineWidth: 2).frame(width: 80, height: 80)
            switch phase {
            case .translating:
                // три точки що крутяться по орбіті 50pt радіус
                ForEach(0..<3) { i in
                    Circle().fill(DS.Color.accent).frame(width: 6, height: 6)
                        .offset(orbitOffset(index: i, angle: spinAngle))
                }
            default:
                Text("M").font(.system(size: 28, weight: .semibold).monospaced())
                    .foregroundStyle(DS.Color.accent)
            }
        }
        .onAppear { spinAngle = phase == .translating ? 360 : 0 }
        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: phase)
    }
}

// DataFlow.swift — animated dots між endpoint і M
struct DataFlow: View {
    let direction: FlowDirection   // .none / .leftToRight / .rightToLeft
    let active: Bool

    var body: some View {
        Canvas { ctx, size in
            // 3-5 точок рухаються вздовж лінії, repeat forever коли active
        }
    }
}

// EndpointBlock.swift — UA / ES блок (без waveform — простіше ніж variant 5)
struct EndpointBlock: View { /* ... */ }
```

**Зміни в `BridgeView.swift`:**

- Замінити поточний `conversationStage` на `ConductorStage` (~70% висоти екрану).
- Archive — простіший: один-рядковий формат на turn (timestamp + UA short + arrow + ES short + latency).
- Lang-pair selector йде в `EndpointBlock` (tap на endpoint → відкриває lang sheet).

**LOC оцінка:** ~250 додати, ~100 видалити. Найбільш дорогий варіант.

## Вплив на DESIGN.md

- Великий нaпис § Three Modes > Bridge: повна заміна на "central conductor stage + archive log".
- Нові компоненти: `ConductorStage`, `ConductorNode`, `EndpointBlock`, `DataFlow`. Кожен з власною motion spec.
- Може потребувати нового § "Animated Components" з правилами щодо тривалості, easing, repeat behaviors.
- Перегляд anti-references — Disrupt-стиль animation близько до zone яку DESIGN.md відкидав. Треба підтвердити що "restrained motion" це OK.

## Коли вибирати

Якщо хочеш зробити Bridge **демонструвальним моментом** продукту — той скрін який ти показуєш на pitch deck, App Store screenshot, marketing video. Це найбільший "wow" з усіх варіантів. Аналог: коли Granola показує AI що думає, або коли Linear показує issue moving across columns — це той самий жанр візуальної опери.

## Коли НЕ вибирати

Якщо timeline тиснe і ти не готовий до 2-3 тижнів роботи над одним екраном (animation polish — нескінченний процес). Або якщо твій cohort — практичні люди які хочуть швидко вирішити проблему перекладу, не дивитись на "AI as theater".
