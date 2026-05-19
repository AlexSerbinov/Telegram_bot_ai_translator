# Варіант 8 — Аудіо-Ріки (без карток, тільки стрім)

## Ментальна модель

**Bridge — це два паралельних аудіо-потоки що тривають у часі.** Викидаємо повністю концепцію discrete turns + cards. Натомість: дві горизонтальні "ріки" аудіо-хвиль, що повільно повзуть зліва направо у часі. Верхня ріка — джерело (мова як її чує мікрофон), нижня — переклад (мова як говорить модель). Над кожною рікою — rolling captions (текст), що "пливе" разом з хвилею. Між двома ріками — мінімальний M-маркер з latency.

Думай про це так: "Це осцилоскоп / спектрограма розмови, що йде. Я не читаю повідомлення — я *спостерігаю потік*."

## Розкладка

```
┌──────────────────────────────────────────────┐
│ Bridge                          Live · 2:47  │
│ TWO-WAY · UK ↔ ES · STREAM MODE              │
│                                              │
│  ──────────── 🇺🇦 SOURCE ────────────         │
│                                              │
│  "...про лікаря — чи можна записатися..."    │ ← rolling caption
│                                              │
│  ≋≋▂▅█▇▅▃▁▂▅█▇▄▂▁▃▅▇▆▄▂▁▂▄▆█▇▅▃▁▂▄▆▇█≋≋    │ ← waveform river
│      ▓▓                          ▓▓          │   "now" cursor
│      now ←                       ← past      │
│                                              │
│  ── M · gpt-realtime · 0.4s latency ──       │
│                                              │
│  ≋≋▁▃▅▇▆▄▂▁▂▅▇▆▄▂▁▂▄▆▇▆▄▂▁▂▄▆▇█▇▅▃▁≋≋      │ ← target waveform
│      ▓▓                                      │
│      now ←                                   │
│                                              │
│  "...el médico — si puedo agendar una cita..."│ ← rolling target caption
│                                              │
│  ──────────── 🇪🇸 TARGET ────────────         │
│                                              │
│ ───────── HISTORICAL TIMELINE ──────────     │
│                                              │
│  02:00 ─────────────────────────────────────│
│  02:30  🇺🇦 "Привіт, як справи?"             │
│         🇪🇸 "Hola, ¿qué tal?"                │
│  03:00  🇪🇸 "Bien, gracias."                 │
│         🇺🇦 "Добре, дякую."                  │
│  ───────────────────────────────────────────│
│                                              │
│                  ╭─────╮                     │
│                  │  🎤  │                    │
│                  ╰─────╯                     │
└──────────────────────────────────────────────┘
```

Дві waveform-річки повзуть зліва направо приблизно зі швидкістю 1pt/100ms — так само як шкала Audacity. "Now cursor" (▓▓) — фіксований на лівому краю ріки; історія тече вправо ("у минуле"). Як прокрутити ріку вправо — побачиш waveform 30 секунд тому з відповідним subtitle.

### Idle (нічого не йде)

```
  ──────────── 🇺🇦 SOURCE ────────────

      (no audio — flat line)
  ──────────────────────────────────────
      ▓▓
      now

  ── M · gpt-realtime · ready ──

      (no audio — flat line)
  ──────────────────────────────────────
      ▓▓

  ──────────── 🇪🇸 TARGET ────────────
```

### Активний стрім

```
─────── 🇺🇦 SOURCE — speaking ───────
"Я хотів запитати про лікаря..."
≋≋▂▅█▇▅▃▁▂▅█▇▄▂▁▃▅▇▆▄▂▁▂▄▆█▇▅▃▁▂▄▆▇█≋≋
    ▓▓                          ▓▓
    now ← (потік повзе вправо)   ← 3s ago

── M · 0.4s latency · ≋ active ──

≋≋▁▃▅▇▆▄▂▁▂▅▇▆▄▂▁▂▄▆▇▆▄▂▁▂▄▆▇█▇▅▃▁≋≋
    ▓▓
    now

"...el médico..."  ← target lagging 0.4s behind
─────── 🇪🇸 TARGET — speaking ───────
```

## Чому це працює

- **Найбільш чесний з усіх варіантів стосовно того що насправді відбувається.** `gpt-realtime` не виробляє "повідомлення" — він виробляє безперервний аудіо-стрім з невеликим лагом. Цей варіант не намагається перекласти цю реальність у "чат" — він показує її як є.
- **Видимий latency.** "Now cursor" на двох ріках *не співпадає* — нижня ріка завжди ~0.4s позаду верхньої. Це робить latency моделі видимим візуально. Користувач бачить що нижня ріка "наздоганяє" верхню.
- **Сильно editorial.** Це аналог spectrogram view у DAW як Logic / Reaper. Це editorial-strict до кінця. Жодних bubbles, жодних карток, тільки чистий час+хвиля+підпис.
- **Прокрутка історії — натуральна.** Тягнеш ріку вправо пальцем = подорож у минуле. Не потрібен окремий "historical view" UI — це є scrub-bar.
- **Найкраще передає "переклад це continuous process, не discrete events".** Це філософська позиція що відрізняє Teycan від Google Translate і всіх інших.

## Що жертвується

- **Дуже далеко від того що користувачі знають.** Більшість translation apps виглядають як messaging. Цей — як аудіо-редактор. Risk: перший-час користувачі плутаються, не знають куди натискати.
- **Подвійна waveform-візуалізація — heavy для CPU/GPU.** Малювати 60Hz хвилю двох потоків одночасно з captions поверх = найбільш draw-intensive UI у проекті. Треба ретельно тестувати на iPhone 11 / 12.
- **Caption rolling — текст рухається.** Користувач має читати рухомий текст. Це когнітивне навантаження, особливо для людей похилого віку (DESIGN.md cohort включає first-18-months Ukrainians — серед них старші батьки). Mitigation: можна "паузити" rolling коли користувач торкається ріки.
- **Архів губиться.** Так, historical timeline унизу — але це грубий sketch. Як знайти конкретну фразу через 30 хвилин? Скрол через 30 хвилин хвилі — нудно. Треба також search bar або keypoints (auto-highlighted utterances).
- **Без turn boundaries — важче "copy / share".** Як виділити одну фразу для копіювання? У variant 4 кожна фраза = окремий блок який ти можеш долго-нажати. Тут — це шматок ріки. Треба будувати UX для "I want to extract this 5-second slice as a saved phrase".

## Implementation sketch

```swift
// AudioRiver.swift — горизонтальна waveform-стрічка з rolling caption
struct AudioRiver: View {
    @ObservedObject var stream: AudioStreamBuffer  // ring buffer ~60s RMS values
    let captionText: String?       // rolling text aligned with current playhead
    let label: String              // "SOURCE" / "TARGET"
    let lang: Language

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack {
                Text("──── \(lang.flag) \(label) ────")
                    .font(DS.Font.eyebrow)
                Spacer()
            }
            if let caption = captionText {
                Text(caption)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textInk)
                    .lineLimit(1)
                    .truncationMode(.head)   // показуємо кінець, бо це "now"
            }
            WaveformCanvas(buffer: stream)
                .frame(height: 48)
                .overlay(alignment: .leading) {
                    NowCursor()
                        .frame(width: 2)
                }
        }
    }
}

// WaveformCanvas — реальний draw 60fps
struct WaveformCanvas: View {
    @ObservedObject var buffer: AudioStreamBuffer

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            Canvas { ctx, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let values = buffer.windowedRMS(width: size.width, atTime: now)
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i)
                    let height = CGFloat(v) * size.height
                    let rect = CGRect(x: x, y: (size.height - height) / 2,
                                      width: 1, height: height)
                    ctx.fill(Path(rect), with: .color(DS.Color.accent.opacity(0.7)))
                }
            }
        }
    }
}

// AudioStreamBuffer — ring buffer ~60s of RMS values
@MainActor
final class AudioStreamBuffer: ObservableObject {
    private var samples: [TimedRMS] = []  // (timestamp, rmsValue)
    func push(rms: Float, at: TimeInterval) { /* ring buffer logic */ }
    func windowedRMS(width: CGFloat, atTime: TimeInterval) -> [Float] { /* ... */ }
}
```

**Зміни в `RealtimeRTCClient`:**

- Hook у `inputAudioBufferHandler` (PCM frames від mic) — порахувати RMS, push у `sourceStreamBuffer`.
- Hook у audio output (PCM frames що граються в speaker) — порахувати RMS, push у `targetStreamBuffer`.
- Hook у `conversation.item.input_audio_transcription.delta` → update sourceCaption.
- Hook у `response.audio_transcript.delta` → update targetCaption.

**Зміни в `BridgeView.swift`:**

- Повна заміна `conversationStage` на 2× `AudioRiver` + M divider.
- Historical timeline — окрема секція нижче, спрощений формат.
- Lang-pair selector — згорнутий у header.

**LOC оцінка:** ~300 додати, ~150 видалити. Найбільший проект з усіх 8.

## Питання інженерії

1. **PCM access.** Чи `RealtimeRTCClient` віддає raw PCM frames доступними для UI? Поточний код у `RealtimeRTCClient.swift` (треба переглянути) — якщо WebRTC peer connection не експонує input PCM frame callback, треба паралельно tap `AVAudioEngine` для RMS вимірювання. Можливо тоді **Soniox** — той самий argument що у Variant 6.

2. **Synchronization.** Source ріка і target ріка повинні мати co-ordinated timeline. Якщо source RMS push timestamp ≠ target RMS push timestamp у тій самій timeline domain — ріки розбіжуться візуально. Треба monotonic clock з спільної точки відліку.

3. **Caption alignment.** Rolling caption має йти "в темпі" з waveform. Це означає: коли transcription delta приходить, треба знати "що на якому часі це було сказано". gpt-realtime іноді віддає transcripts post-hoc batchово.

## Вплив на DESIGN.md

- Перегляд **філософії** Bridge. Поточна DESIGN.md описує його як "conversation stage with turn cards". Цей варіант каже "Bridge — stream visualization, не chat". Це найбільший філософський поворот.
- Нові компоненти: `AudioRiver`, `WaveformCanvas`, `NowCursor`, `AudioStreamBuffer`.
- Може потребувати нової секції § Streaming Visualization з правилами щодо waveform draw rate, color, density.
- Може зробити нерелевантною секцію § Bridge Turn Cards — або, навпаки, експанд її до того як "compact stream" і "card archive" співіснують.

## Коли вибирати

Якщо хочеш зробити Teycan *не такою як інші translation apps*. Це найбільш брендова, найбільш авторська і найбільш ризикована з усіх 8 варіантів. Це той варіант про який пишуть у дизайн-блогах ("how Teycan reimagined translation UI as audio visualization"). Це варіант для Founder Edition cohort що цінує "premium tool that looks like nothing else".

## Коли НЕ вибирати

Якщо метрика успіху — "ordinary user can pick up the app and use it within 60 seconds without confusion". Цей варіант *вимагає* onboarding-скрин що пояснює "це не чат, це аудіо-стрім". Бар входу вищий.
