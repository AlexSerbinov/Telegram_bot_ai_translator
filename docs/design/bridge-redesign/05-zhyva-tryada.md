# Варіант 5 — Жива тріада (еволюція Variant 1)

## Ментальна модель

**Кастінг з трьох акторів, кожен — реактивний у real-time.** Зверху сцени стоять три "капсули": 🇺🇦 UA · M · 🇪🇸 ES. Але це не статичні pill-кнопки — кожна капсула має власний live-стан (waveform / pulse / "thinking" / "speaking"), що відображає *поточну фазу циклу перекладу* у `gpt-realtime`. Картки turn-ів накопичуються нижче як архів, але "правда" про те, що відбувається ЗАРАЗ — у верхній тріаді.

Думай про це так: "Це 3 актори на сцені. У будь-який момент я бачу хто говорить, хто думає, хто слухає. Архів того, що було сказано — нижче."

## Розкладка по фазах

```
ФАЗА 1 — IDLE (нічого не відбувається)
─────────────────────────────────────────
   ┌─────────┐    ╭───╮    ┌─────────┐
   │ 🇺🇦 UA   │    │ M │    │ 🇪🇸 ES   │
   │   idle  │    ╰───╯    │   idle  │
   └─────────┘    ready    └─────────┘

   Tap mic — будь-хто може заговорити.


ФАЗА 2 — UA SPEAKING (українець говорить)
─────────────────────────────────────────
   ┌─────────┐    ╭───╮    ┌─────────┐
   │ 🇺🇦 UA   │    │ M │    │ 🇪🇸 ES   │
   │ ≋≋≋≋≋   │ ←─ │   │    │  ...    │
   │ live    │    ╰───╯    │ waiting │
   └─────────┘  listening  └─────────┘

   "Привіт, як справи сьогодні..."  ← live partial
                                       (від gpt-realtime
                                        input_audio_transcription)


ФАЗА 3 — M TRANSLATING (UA замовк, M генерує переклад)
─────────────────────────────────────────
   ┌─────────┐    ╭───╮    ┌─────────┐
   │ 🇺🇦 UA ✓ │    │ M ◐ │   │ 🇪🇸 ES   │
   │  done   │    │ ··· │   │ waiting │
   └─────────┘    ╰───╯    └─────────┘
                  thinking
   "Привіт, як справи сьогодні?"  ← фінальний UA


ФАЗА 4 — ES HEARING (M вимовляє переклад вголос для ES)
─────────────────────────────────────────
   ┌─────────┐    ╭───╮    ┌─────────┐
   │ 🇺🇦 UA ✓ │    │ M ✓ │ ─→ │ 🇪🇸 ES   │
   │  done   │    │     │   │ 🔊 ≋≋   │
   └─────────┘    ╰───╯    │ playing │
                           └─────────┘
   "Hola, ¿cómo estás hoy..."  ← live target caption
                                  (по мірі того як M
                                   випльовує audio_delta)


ФАЗА 5 — ЗАВЕРШЕННЯ ЦИКЛУ (картка падає в архів)
─────────────────────────────────────────
   ┌─────────┐    ╭───╮    ┌─────────┐
   │ 🇺🇦 UA   │    │ M │    │ 🇪🇸 ES   │
   │  idle   │    ╰───╯    │  idle   │
   └─────────┘    ready    └─────────┘

   ── архів ──
   UA → M → ES   02:47   0.8s
   ┌────────────────────────────────────┐
   │ Привіт, як справи сьогодні?        │
   │ ──────────────                     │
   │ Hola, ¿cómo estás hoy?             │
   └────────────────────────────────────┘
```

## Повна сцена (з історією)

```
┌──────────────────────────────────────────────┐
│ Bridge                          Live · 2:47  │
│                                              │
│   ┌─────────┐    ╭───╮    ┌─────────┐        │
│   │ 🇺🇦 UA   │    │ M ◐ │   │ 🇪🇸 ES   │  ← ЖИВА  │
│   │ ≋≋≋     │ ←─ │ ··· │   │ waiting │     ТРІАДА│
│   └─────────┘    ╰───╯    └─────────┘        │
│                                              │
│   "Я хотів запитати про лікаря..."           │
│        ← live partial UA (поки говорить)     │
│                                              │
│ ────────────── АРХІВ ───────────────         │
│                                              │
│   UA → M → ES                  02:47  0.8s   │
│   ┌────────────────────────────────────┐     │
│   │ Привіт, як справи сьогодні?        │     │
│   │ ──                                 │     │
│   │ Hola, ¿cómo estás hoy?             │     │
│   └────────────────────────────────────┘     │
│                                              │
│                    ES → M → UA   02:53  0.6s │
│        ┌────────────────────────────────────┐│
│        │ Bien, gracias. ¿Y tú?              ││
│        │ ──                                 ││
│        │ Добре, дякую. А ти?                ││
│        └────────────────────────────────────┘│
│                                              │
│                  ╭─────╮                     │
│                  │  🎤  │                    │
│                  ╰─────╯                     │
│           SPEAKING · AUTO-DETECT             │
└──────────────────────────────────────────────┘
```

## Чому це працює

- **Зберігає мізки варіанту 1** (тріада акторів зверху) — додає те, що його робить *живим*: кожен актор має 4 стани (idle / live / thinking / playing), які синхронізовані з реальними подіями `gpt-realtime` (input_audio_buffer.speech_started, response.audio.delta, тощо).
- **Live caption над тріадою — це поточна "правда".** Не пливе вгору як стрічка чату. Залишається на місці, оновлюється in-place. Користувач завжди знає де дивитися щоб побачити "що зараз".
- **Архів turn-ів зберігається.** Коли цикл завершився, картка ковзає донизу як вже-готовий запис. Це задовольняє use-case "хочу проскролити що було" без жертв до live-стану.
- **Тактильно зрозуміло.** Якщо я українець і бачу що моя капсула пульсує — я знаю що мене *чують*. Бачу що M пульсує — мене *перекладають*. Бачу що ES капсула пульсує — мене *чують з іншого боку*. Це emotional feedback, якого ніколи не давав turn-based чат.

## Що жертвується

- **Stateful UI = більше bugs.** Якщо `gpt-realtime` глюкне і застрягне в "M thinking" — UI зависне у фазі 3 назавжди. Треба timeouts + recovery. Поточний код вже має `manager.isRunning` — треба додати ще `.speechActive`, `.translating`, `.speaking`.
- **Реклама — це маленький шрифт.** Live caption над тріадою у фазі 2 і фазі 4 — два різні живі тексти у тому самому місці. Може заплутати ("зараз я бачу що я сказав чи що мені відповіли?"). Mitigation: різні кольори (UA caption — text.ink, ES caption — accent), або іконка біля кожного.
- **Архів забирає дуже багато простору на маленькому екрані.** Жива тріада + caption = ~120pt зверху. На iPhone SE залишається ~300pt на архів. Можливо колапсувати тріаду у "compact mode" коли архів довший за N карток.

## Implementation sketch

```swift
// LiveTriad.swift — три-акторна капсульна сцена з real-time станами
enum ActorState {
    case idle
    case speaking          // VAD detected speech
    case finished          // utterance closed, waiting for translation
    case thinking          // only M — generating response
    case playing           // only target — audio_delta being delivered
}

struct ActorPill: View {
    let lang: Language?    // nil for M
    let state: ActorState

    var body: some View {
        VStack(spacing: 4) {
            // Flag + code OR "M"
            Text(lang.map { "\($0.flag) \($0.code.uppercased())" } ?? "M")
                .font(DS.Font.eyebrow)

            // State indicator
            switch state {
            case .idle: idleDot
            case .speaking: waveformAnimation
            case .finished: Text("✓").foregroundStyle(DS.Color.semanticSuccess)
            case .thinking: thinkingDots
            case .playing: speakerWithWaveform
            }
        }
    }
}

struct LiveTriad: View {
    @ObservedObject var session: BridgeSessionManager
    var body: some View {
        VStack(spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                ActorPill(lang: session.langA, state: session.actorAState)
                ActorPill(lang: nil, state: session.modelState)
                ActorPill(lang: session.langB, state: session.actorBState)
            }
            if let caption = session.liveCaption {
                Text(caption)
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(captionColor(for: session.activeActor))
                    .transition(.opacity)
            }
        }
    }
}
```

**Зміни в `BridgeSessionManager`:**

- Додати enum `BridgeCyclePhase` (idle, listening, translating, speaking) і публікувати поточну фазу.
- Підписатися на `RealtimeRTCClient` events:
  - `input_audio_buffer.speech_started` → phase = .listening, actorState UA/ES = .speaking
  - `input_audio_buffer.speech_stopped` → actorState .finished
  - `response.created` → modelState = .thinking
  - `response.audio.delta` (перший delta) → modelState = .finished, targetActor = .playing
  - `response.done` → reset to .idle, перенести completed turn у `messages[]`

**Зміни в `BridgeView.swift`:**

- Замінити поточний lang-pair selector на `LiveTriad`.
- Архів turn-карток рендериться нижче через `ScrollView { VStack { ... } }`.

**LOC оцінка:** ~120 додати (LiveTriad + ActorPill + animation states + manager events), ~30 видалити (стара pair-selector + isolated ModelNode).

## Вплив на DESIGN.md

- Великий апдейт § Three Modes > Bridge: layout рухається від "axis + nodes" до "3-actor live triad + archive".
- Додати `ActorPill` і `LiveTriad` як перші компоненти у DESIGN.md що мають **stateful animation specs**. Поточна Motion-секція має лише static transitions — треба додати state-machine specs.
- Тримати `ModelNode` як deprecated alias для `ActorPill(lang: nil, state: .idle)` поки не змігруємо інші модулі.

## Коли вибирати

Якщо хочеш, щоб користувач *відчував* як працює realtime — як симфонія, де кожен інструмент має свою партію. Найкраще для founder-edition cohort у DESIGN.md (Українці у Іспанії на медичних/легальних розмовах) — це *моменти високої напруги*, де emotional feedback ("мене перекладають зараз") заспокоює нерви.

## Коли НЕ вибирати

Якщо треба швидко зашипити (це найдорожча імплементація з усіх 8 варіантів через state machine). Або якщо команда не готова дебажити stuck states у realtime потоці.
