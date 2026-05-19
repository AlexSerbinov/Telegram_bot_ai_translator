# Варіант 6 — Канали + Живий Шар (еволюція Variant 3)

## Ментальна модель

**Дві колонки-канали (як у Variant 3), але кожна колонка має "живий шар" зверху.** Поки користувач говорить, у верхній частині його колонки з'являються streaming partial-транскрипти — italic, напівпрозорі, оновлюються 5-10 разів на секунду. Коли VAD детектить кінець utterance — partial *фіналізується* і ковзає донизу як постійна картка-запис. Між колонками — `TranslatorDock` з реальним waveform-ом audio output моделі.

Думай про це так: "Дві стенограф-стрічки що пишуться одночасно. Зверху — те, що пишеться зараз (текуче, нечітке). Нижче — те, що вже зафіксовано як official record. Між ними — перекладач який живе своїм життям."

## Розкладка

### Активна сесія (UA говорить, M вже почав перекладати)

```
┌──────────────────────────────────────────────┐
│ Bridge                          Live · 2:47  │
│                                              │
│  🇺🇦 UA SPEAKER         ║         🇪🇸 ES SPEAKER│
│  ──────────────         ║         ─────────────│
│                         ║                      │
│  ╭──── ЖИВИЙ ШАР ────╮   ║                      │
│  │ Я хотів запитати  │   ║  ╭── ЖИВИЙ ШАР ──╮   │
│  │ про лікаря —      │ ─→║─→│ Quería pregun-│   │
│  │ чи можна записа.. │   ║  │ tar sobre el  │   │
│  │ ≋≋≋ listening     │   ║  │ médico — si.. │   │
│  ╰───────────────────╯   ║  │ ≋≋ speaking    │   │
│                         ║  ╰────────────────╯   │
│  ── архів ──             ║  ── архів ──         │
│                         ║                      │
│  ┌──────────────────┐   ║                      │
│  │ Привіт, як       │   ║                      │
│  │ справи?          │   ║                      │
│  │ ··               │   ║                      │
│  │ Hola, ¿qué tal?  │   ║                      │
│  │ 02:47 · 0.8s     │   ║                      │
│  └──────────────────┘   ║                      │
│                         ║   ┌──────────────────┐│
│                         ║   │ Bien, gracias.   ││
│                         ║   │ ¿Y tú?           ││
│                         ║   │ ··               ││
│                         ║   │ Добре, дякую.    ││
│                         ║   │ 02:53 · 0.6s     ││
│                         ║   └──────────────────┘│
│                         ║                      │
│  ════════════ ╭───╮ ═══════════════           │
│      M · gpt  │ M │ ≋≋≋ live · 0.4s          │
│               ╰───╯ ┃┃┃┃┃┃ waveform           │
│                                              │
│                  ╭─────╮                     │
│                  │  🎤  │                    │
│                  ╰─────╯                     │
└──────────────────────────────────────────────┘
```

### Idle (нічого не відбувається)

```
  🇺🇦 UA SPEAKER         ║         🇪🇸 ES SPEAKER
  ──────────────         ║         ──────────────

                         ║
       Тапни мікрофон. Канали почнуть писатися.
                         ║

  ════════════ ╭───╮ ═══════════════
                │ M │ ready
                ╰───╯
```

### Перехід (partial → final card)

```
ДО (live):
  ╭──── ЖИВИЙ ШАР ────╮
  │ Привіт, як справи │ ← italic, opacity 0.6
  │ ≋≋≋ listening     │
  ╰───────────────────╯

ПІСЛЯ (VAD detected silence):
  ┌──────────────────┐
  │ Привіт, як       │ ← solid, opacity 1.0
  │ справи?          │   slide-down animation
  │ ··               │   200ms ease-out
  │ Hola, ¿qué tal?  │
  │ 02:47 · 0.8s     │
  └──────────────────┘
```

## Чому це працює

- **Розв'язує найбільшу скаргу до Variant 3:** у попередньому варіанті бракувало "що ЗАРАЗ відбувається". Тут — два живих шари зверху колонок дають цей сигнал ідеально. Користувач завжди бачить що його чують ("мої слова з'являються!") і що співрозмовнику говориться ("текст у його шарі з'являється!").
- **Чітко розрізняє "partial" і "final".** Стилістично: partial — italic, прозорість 0.6, мерехтить (≋≋≋). Final — solid, opacity 1.0, з timestamp + latency. Користувач інтуїтивно розуміє "це чернетка, а це запис".
- **TranslatorDock тепер реально живий.** З справжнім audio waveform від `response.audio.delta` (можна порахувати RMS з PCM frames у RealtimeRTCClient). M перестає бути символом і стає видимим інструментом.
- **Найкраще для високих ставок.** Якщо ти ведеш медичну розмову — побачити що твої слова реально записалися (живий шар → fixed card) дає психологічну впевненість. Це найбільш "stenographer's office" з усіх варіантів.

## Що жертвується

- **Складність stream-обробки.** Потрібен access до partial transcripts від `gpt-realtime`. Зараз у `RealtimeRTCClient` ми отримуємо `conversation.item.input_audio_transcription.delta` (для UA) і `response.audio_transcript.delta` (для ES). Треба ці події прокинути у UI поверх існуючого `manager.messages`. Не складно, але новий код.
- **Якщо чути партіали від gpt-realtime недостатньо швидко** (вони приходять після VAD, не під час) — *тоді* можна додати Soniox паралельно (через `STTService` що вже існує у `services/`). Це інженерна гілка — давай вирішимо окремо.
- **Дві колонки = той самий мінус що у Variant 3.** Текст у вузький стовпчик, переноситься часто. Mitigation як раніше: дозволити одній колонці бути ширшою коли інша порожня.
- **Тонкий вертикальний divider між колонками** — той самий ризик "scratch line" як був з v3.0 axis. Mitigation: divider тільки тоді коли обидві колонки мають контент. Або робити divider hairline.subtle а не hairline.

## Implementation sketch

```swift
// LiveLayer.swift — partial transcript stream поверх колонки
struct LiveLayer: View {
    let partialText: String
    let isListening: Bool   // якщо false — порожній шар

    var body: some View {
        Group {
            if isListening {
                VStack(alignment: .leading, spacing: 4) {
                    Text(partialText)
                        .font(DS.Font.bodyEmphasis.italic())
                        .foregroundStyle(DS.Color.textInk.opacity(0.6))
                    HStack(spacing: 4) {
                        WaveformIndicator(active: true)
                        Text("listening")
                            .font(DS.Font.eyebrow)
                            .foregroundStyle(DS.Color.textSubtle)
                    }
                }
                .padding(DS.Space.md)
                .background(DS.Color.bgSurface.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(DS.Color.hairline, lineWidth: DS.Stroke.hairline)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// TranslatorDock.swift — реальний waveform від audio_delta RMS
struct TranslatorDock: View {
    let isLive: Bool
    let waveformBuckets: [Float]   // ~32 RMS values, оновлюється 30Hz
    let modelName: String
    let lastLatencyMs: Int?

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            DividerLine()
            ModelNode(isActive: isLive)
            Text("M · \(modelName)").font(DS.Font.eyebrow)
            Waveform(values: waveformBuckets)
                .frame(width: 80, height: 16)
            if let ms = lastLatencyMs {
                Text("\(Double(ms) / 1000, specifier: "%.1f")s").font(DS.Font.mono)
            }
            DividerLine()
        }
    }
}

// ChannelColumn.swift — змінений з Variant 3 щоб включати LiveLayer
struct ChannelColumn: View {
    let speaker: Language
    let livePartial: String?
    let isLiveActive: Bool
    let archivedTurns: [BridgeMessage]
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: DS.Space.md) {
            speakerHeader
            LiveLayer(partialText: livePartial ?? "", isListening: isLiveActive)
            EyebrowLabel(text: "АРХІВ", color: DS.Color.textSubtle)
            ForEach(archivedTurns) { archivedCard($0) }
        }
    }
}
```

**Зміни в `BridgeSessionManager`:**

- Додати `@Published var livePartialA: String?` і `@Published var livePartialB: String?` (партіал по колонці).
- Підписатися на `conversation.item.input_audio_transcription.delta` події з RealtimeRTCClient, кидати у відповідну колонку згідно детектованої мови.
- При `response.done` — перенести фіналізований текст з partial у `messages[]`, очистити partial.
- Додати `@Published var audioWaveformBuckets: [Float]` для TranslatorDock, оновлюваний з RMS PCM frames від response.audio.delta.

**LOC оцінка:** ~150 додати, ~70 видалити (заміщення Variant 3 без живого шару).

## Питання інженерії що треба вирішити

1. **STT якість партіалів.** `gpt-realtime` віддає партіали лише після того як VAD каже "speech_stopped" — тобто партіал з'являється у нашому UI з затримкою ~300-500ms після того як користувач замовк. Якщо хочемо реально-час партіали по мірі того як він говорить — треба паралельно ганяти Soniox (бо він стрімить per-word). Тоді UI показує Soniox-партіал у живому шарі (для swift visual feedback), а gpt-realtime робить сам аудіо-переклад.

   - **За:** instant feedback, користувач бачить своє ж мовлення майже без затримки.
   - **Проти:** дублювання audio stream (треба роздвоювати mic input через `AVAudioPCMBuffer` копіювання), плюс додатковий cost Soniox API.
   - **Варіант компромісу:** Soniox тільки якщо `BridgeSettings.useHighFidelityCaptions = true` (off by default).

2. **Final-card злиття з partial.** Коли partial фіналізується, треба згладжену анімацію slide-down. Якщо текст фіналізованого turn-у відрізняється від останнього partial (gpt-realtime іноді корегує) — show diff briefly або просто snap-replace.

3. **Buffer audio waveform.** `response.audio.delta` приходить як PCM16 chunks ~50ms each. Треба buffer останніх ~32 chunks, рахувати RMS, малювати waveform. Реалізація: `CircularBuffer<Float>` в `RealtimeRTCClient.audioOutputHandler`.

## Вплив на DESIGN.md

- Cтворити нову секцію § Live State Components з повним state-machine описом для LiveLayer і TranslatorDock.
- Apdate § Three Modes > Bridge: канали з живим шаром стають основною розкладкою.
- Додати специфікацію `Waveform` компонента (висота 16pt, 32 buckets, RMS normalize 0–1, accent fill).
- Додати правило: "partial text — italic + opacity 0.6, final text — regular + opacity 1.0" як універсальний indicator для streaming UIs у проекті.

## Коли вибирати

Якщо хочеш найбільш *чесний* live UI — той, який реально віддзеркалює стан системи без прикрас. Це варіант для людей хто цінує "I can see what the machine is doing" (Linear / Granola / Stripe Workflows philosophy).

## Коли НЕ вибирати

Якщо команда не готова інвестувати в новий event pipeline у `RealtimeRTCClient` + Soniox синхронізацію (якщо вирішимо її додати). Це найбільш engineering-heavy варіант з усіх 8.
