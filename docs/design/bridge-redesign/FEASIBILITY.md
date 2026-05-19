# Feasibility-аналіз варіантів V5–V8

**Дата:** 2026-05-12
**Контекст:** перевірка чи realtime-aware варіанти (V5, V6, V7, V8) реально можна зробити поверх існуючої iOS-кодової бази.

## TL;DR

| Варіант | Feasibility | Головний блокер |
|---------|-------------|-----------------|
| **V5 — Жива тріада** | **9 / 10. EASY** | Жодного. Усі сигнали вже є. |
| **V6 — Канали + Живий шар** | **7 / 10. MOSTLY EASY** | Реальний waveform M's output потребує WebRTC PCM tap (або синтетичний waveform — fallback). |
| **V7 — Диригент** | **8 / 10. EASY-MEDIUM** | Жодного функціонального. Heavy animation work. |
| **V8 — Аудіо-ріки** | **5 / 10. PARTIAL** | Source river — easy. Target river — той самий WebRTC output PCM блокер. Без нього концепція "дві ріки" втрачає половину сенсу. |

## Що вже є в коді (важливі знахідки)

Я думав що багато інфраструктури треба буде будувати — насправді все вже там:

### 1. Soniox parallel STT — ВЖЕ В ПРОДІ на iOS Bridge

`BridgeSettings.useSoniox` (default `true` за `BridgeSettings.swift:101`) піднімає паралельний WebSocket-стрім до Soniox `stt-rt-v4`. Реалізація у:
- `Sources/STT/SonioxLiveSTT.swift` — WebSocket actor + sliding-window merger
- `Sources/Audio/PCMStreamRecorder.swift` — таплянь AVAudioEngine паралельно WebRTC mic, `configureSession: false` щоб не зачепити `.voiceChat` категорію
- `Sources/Features/Bridge/BridgeSessionManager.swift:222-340` — повна orchestrator-логіка з 4-секундним watchdog, warm-up grace, fallback на OpenAI gpt-4o-transcribe

Це означає: **те що я в попередньому туру описував як гіпотетичну "Soniox-гілку" — вже працює сьогодні**. Усі варіанти V5–V8 можуть розраховувати на high-quality per-word user partials з коробки.

**Caveat:** watchdog у `BridgeSessionManager.swift:268-278` залишає LOG-предупреждення якщо Soniox armed але 0 PCM chunks за 4s — це означає AVAudioEngine конфліктує з WebRTC за input bus. У такому разі автоматично відкочуємось до OpenAI partials. Тобто Soniox це best-effort, а не гарантія.

### 2. Усі realtime events — вже декодуються

`Sources/WebRTC/RealtimeEvent.swift` парсить:
- `input_audio_buffer.speech_started` → `.inputAudioBufferSpeechStarted` ✓ (VAD початок мовлення)
- `input_audio_buffer.speech_stopped` → `.inputAudioBufferSpeechStopped` ✓ (VAD кінець)
- `conversation.item.input_audio_transcription.delta` → `.inputTranscriptDelta` ✓ (streaming user text)
- `response.audio_transcript.delta` → `.outputTranscriptDelta` ✓ (streaming model text)
- `response.audio_transcript.done` → `.outputTranscriptDone` ✓ (final model text)
- `output_audio_buffer.started` → `.outputAudioBufferStarted` ✓ — **ВАЖЛИВО: вже парситься, але currently не використовується** (`BridgeSessionManager.swift:413` — просто `break`). Це ідеальний сигнал для V5/V7 "ES playing" фази.
- `response.done(status)` → `.responseDone(status:)` ✓ з distinction `completed` vs `cancelled` (Cancel-aware — fix для "сильно вдихнули = phantom turn" bug)

### 3. Стан-машина повідомлень — частково готова

`BridgeMessage.isFinalized: Bool` (`BridgeMessage.swift:10`) розрізняє streaming partial від final. Поточний UI використовує тільки для відображення `…` або фінального тексту — але це готовий backbone для "partial italic / final solid" патерну з V6.

### 4. Чого НЕМАЄ (і це блокери для V6/V8)

**WebRTC не експонує raw PCM frames для аудіо**, ні input (бо WebRTC сам ним керує через свою AVAudioEngine instance) ні output (бо WebRTC грає його прямо у speaker через native render pipeline). Це означає:

- **Input waveform** — *можна* отримати окремо: `PCMStreamRecorder` вже таплянь mic паралельно для Soniox. Можемо рахувати RMS з тих самих PCM chunks (~50ms кожен) без додаткового overhead.
- **Output waveform (M's voice)** — *немає прямого API*. WebRTC's `RTCAudioTrack` для remote stream НЕ має `audioBufferCallback` доступного назовні. Workarounds:
  1. **Native WebRTC patch:** копати `WebRTC.framework` headers і знаходити `RTCAudioSink` (existed in some forks). Можливо, але збільшує binary size + ризик ламань на upgrade WebRTC.
  2. **AVAudioSession tap output bus:** technically possible через `AVAudioEngine.outputNode.installTap`, але це WILL конфліктувати з WebRTC's audio session. Echo cancellation поламається.
  3. **Synthetic waveform driven by `outputTranscriptDelta` cadence:** dummy bars що "пульсують" коли delta-події приходять. Не справжній RMS, але візуально читабельно. **Найбезпечніший fallback.**
  4. **Synthetic waveform driven by `outputAudioBufferStarted` + estimated duration:** анімуємо waveform від моменту події до прогнозованого закінчення (estimate з кількості символів × ~50ms/символ). Грубо, але візуально OK.

**Висновок:** реальний M output waveform потребує R&D на WebRTC SDK. Без нього V6 і V8 використовують synthetic. Це робить V8 особливо болючим бо "ріки" — це сама його суть.

---

## V5 — Жива Тріада: feasibility deep-dive

**Score: 9 / 10. ШИПАБЕЛЬНО ЗА 2-3 ДНІ.**

### Що додати

1. **`BridgeCyclePhase` enum** у `BridgeSessionManager`:
   ```swift
   enum CyclePhase {
       case idle
       case sourceListening(lang: String)   // VAD active, user speaking
       case sourceFinished(lang: String)    // VAD stopped, awaiting M
       case translating(sourceLang: String, targetLang: String)
       case targetSpeaking(lang: String)    // M's audio playing through speaker
   }
   private(set) var phase: CyclePhase = .idle
   ```

2. **Wiring подій → phase** у `handle(event:)`:
   - `.inputAudioBufferSpeechStarted` → `.sourceListening(lang: lastUserLang ?? sessionLangA)`
   - `.inputAudioBufferSpeechStopped` → `.sourceFinished(...)`
   - Перший `.outputTranscriptDelta` → `.translating(...)`
   - `.outputAudioBufferStarted` → `.targetSpeaking(lang: opposite of sourceLang)` ← **ось де нарешті оживає поки невикористана подія**
   - `.responseDone(completed)` → `.idle` (після короткого `.targetSpeaking` finish-tail)

3. **`LiveTriad` view** (новий SwiftUI компонент) — слухає `manager.phase` та `manager.messages.last?` (для live caption).

4. **`ActorPill` view** з 5 станами (idle / speaking / finished / thinking / playing) + simple animations.

### Що НЕ треба додавати

- Soniox: вже там.
- Будь-який новий event parsing: усе є.
- Будь-який audio access: state машина працює виключно на data-channel events.

### Estimated LOC

~120 нового UI коду + ~40 LOC у `BridgeSessionManager` для phase publishing. Видалити: ~30 LOC поточного pair-selector.

### Ризики

- **Анімації між фазами** мають бути швидкі (<200ms) — інакше юзер бачить "вмираючий" UI коли M починає говорити. Easy to tune.
- **Edge case:** користувач починає говорити поки M все ще грає попередню відповідь. Поточний код це обробляє через `responseDone(cancelled)` логіку. Phase повинна стрибнути назад у `.sourceListening` без повторного `idle`.

---

## V6 — Канали + Живий Шар: feasibility deep-dive

**Score: 7 / 10. ШИПАБЕЛЬНО ЗА 4-5 ДНІВ.** (Або 6/10 якщо хочеш реальний output waveform.)

### Що додати

1. **Filter messages by language** — потрібно дві колекції:
   ```swift
   var messagesA: [BridgeMessage] { messages.filter { $0.language == sessionLangA } }
   var messagesB: [BridgeMessage] { messages.filter { $0.language == sessionLangB } }
   ```
   Тривіально, бо `language` вже заповнюється `BridgeLanguageGuesser`.

2. **LiveLayer** — показує `messages.last(where: { !$0.isFinalized })` як italic semi-opaque card зверху відповідної колонки. Filter on language. Animation: transition `.opacity.combined(with: .move(edge: .top))` коли `isFinalized` стає `true`.

3. **TranslatorDock** з waveform — тут великий вибір:

   **Option A (real input + synthetic output):**
   - Source waveform: підключити RMS calculator до `PCMStreamRecorder` chunks. Easy — той самий audio path що йде у Soniox.
   - Target waveform: synthetic, driven by `outputTranscriptDelta` rate. Коли deltas приходять часто — bars високі. Коли пауза — низькі. Не справжній RMS, але skinny enough для editorial vibe.

   **Option B (real both sides):** копати WebRTC. 1-2 тижні R&D з невідомим результатом. **Не рекомендую без явної мотивації.**

   **Option C (no output waveform, тільки pulse indicator):** скоротити dock до "M · gpt-realtime · 0.4s" текстового статусу + pulse dot. Простіше, чесніше, vs псевдо-waveform. **Мій choice.**

### Що НЕ треба додавати

- Streaming partials: вже працюють через `appendDelta` + `BridgeMessage.isFinalized`.
- Soniox: вже там, дає партіали юзеру.
- Language splitting: `BridgeLanguageGuesser` вже працює.

### Estimated LOC

- Layout: ~100 нового UI коду (ChannelColumn × 2, LiveLayer, TranslatorDock).
- Waveform Canvas (якщо real input + synthetic output): ~80 LOC у нову `WaveformView.swift` + `AudioStreamBuffer` (ring buffer).
- Hook RMS in PCMStreamRecorder: ~20 LOC.

### Ризики

- **Вертикальний divider між колонками** — той самий visual ризик "scratch through text" як був з v3.0 axis. Mitigation: divider тільки при контенті в обох колонках, або `hairline.subtle` замість `hairline`.
- **Card width на iPhone SE / mini** — 175pt на колонку, довгі речення переносяться часто. Mitigation: дозволити active column бути ширшою коли інша порожня (dynamic split 70/30 в idle, 50/50 коли є контент у обох).
- **Якщо вибрати Option C** (без output waveform) — варіант ризикує бути менш "wow". Але це чесніший варіант.

---

## V7 — Диригент: feasibility deep-dive

**Score: 8 / 10. ШИПАБЕЛЬНО ЗА 5-7 ДНІВ.**

Усі функціональні сигнали — ті самі що у V5 (phase enum). Різниця — суто візуальна. Тому feasibility ≈ V5 + extra animation budget.

### Що додати

1. **`BridgeCyclePhase`** — той самий enum що у V5.

2. **ConductorStage** layout — left endpoint, animated dataflow, central M, animated dataflow, right endpoint.

3. **Animated dots flowing along path** — `Canvas { TimelineView { ... } }` що малює 3-5 точок що рухаються вздовж лінії. Phase-залежне напрямок та активність.

4. **Whirling M під час translating** — три точки на орбіті 50pt радіус, `linear(duration: 1.2).repeatForever` rotation.

5. **Caption box** — centered, fades in/out per phase.

### Що НЕ треба додавати

- Audio access: жодного. Усе animation-driven by phase.
- Soniox: вже там для partial captions.

### Estimated LOC

~250 нового UI коду. Animation polish — ще 30%. Готуйся до 5-7 днів тільки на цей screen.

### Ризики

- **Performance на iPhone 11 / 12 mini.** `TimelineView(.animation)` + `Canvas` draws 60Hz може просісти на старіших девайсах. Test early.
- **Anti-Duolingo violation.** Animated dots + whirling M близько до території яку DESIGN.md явно відкидає. Mitigation: extremely restrained — monochrome dots, тривалість 200ms transitions, без bounce/spring easing.

---

## V8 — Аудіо-Ріки: feasibility deep-dive

**Score: 5 / 10. ПОТРЕБУЄ КОМПРОМІСУ. 2 тижні мінімум.**

### Що можна зробити

1. **Source river** — easy. RMS з PCMStreamRecorder, ring buffer ~60s, Canvas draw 60Hz. Готово.

2. **Rolling captions** — easy. `outputTranscriptDelta` дає текст, але без word-timestamps. Можемо align з power-spectrum peaks (приблизно — "там де голосно у waveform = там слово").

3. **Historical timeline** — easy. Filter `messages` by timestamp, render compact rows.

### Чого НЕ можна зробити (без R&D)

- **Target river (модель's voice waveform)** — той самий блокер: WebRTC не дає output PCM. Те саме як V6.

### Якщо погоджуємось на synthetic target river

- Synthetic варіант 1: бари висота прив'язана до `outputTranscriptDelta` cadence (rate of deltas → "loudness")
- Synthetic варіант 2: бари висота прив'язана до `outputAudioBufferStarted` + duration estimate from char count

Обидва варіанти візуально працюють, але **це більше не "осцилоскоп" — це декорація**. Концепція V8 ("ти бачиш справжню машинерію") компрометується.

### Чесна рекомендація

V8 без real target river — це фактично V4 (transcript log) з декоративним source waveform зверху. Менш сміливий ніж його pitch. Якщо хочемо V8 у повній силі — це WebRTC R&D project на 2-3 тижні з невідомим успіхом.

### Estimated LOC (synthetic version)

~300 + week R&D на WebRTC якщо хочемо real both-side waveforms.

### Ризики

- **CPU/GPU draw cost.** Дві waveform canvas 60Hz + captions + cursors — найбільш intensive UI у проекті.
- **Onboarding cliff.** Користувачі не розуміють що це. Потрібен tutorial.

---

## Моя рекомендація

**Шипуй V5 спочатку.** Він використовує усе що вже є у коді, додає те найважливіше що зараз бракує (видимий live state), і пейн-фрі імплементація. Це фундамент.

**Потім, якщо хочеш дослідити далі — V6 з Option C (без output waveform).** Канали + живий шар + текстовий dock. Більш rigorous editorial vibe. Reuse V5's phase enum.

**V7 і V8 — на потім.** V7 — як marketing screen / promo concept. V8 — після того як WebRTC PCM tap буде вирішений (або визнаний нездійсненним).

## Питання які треба вирішити перед стартом

1. **Чи лишаємо Soniox як default ON?** Зараз default `true`. Усі V5–V8 спираються на high-quality partials, але код вже має fallback на OpenAI коли Soniox starves. Думаю — лишити як є.
2. **Чи додаємо `outputAudioBufferStarted` як активний сигнал?** Зараз він парситься але ігнорується. Для V5/V7 — обов'язково треба. Тривіальний hook.
3. **Чи погоджуємось на synthetic target waveform у V6 (якщо вибираємо V6)?** Bias-confirmation: чесне рішення = так, бо real PCM tap WebRTC — це 1-2 тижні R&D.

Скажи свій choice і йду в код.
