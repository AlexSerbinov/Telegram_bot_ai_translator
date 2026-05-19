# Bridge tab — redesign exploration

**Дата:** 2026-05-12
**Автор:** AI pair
**Статус:** Exploration — варіанти 1–4 (текстові, turn-based) + 5–8 (realtime-aware)

## Проблема

Bridge на iOS працює на `gpt-realtime-translate` через WebRTC — це **continuous audio stream**, а не turn-based чат. Поточна розкладка трактує переклад як discrete messages (картки що з'являються по одній), але реальність ближче до:

```
user speaks UA continuously →
gpt-realtime streams audio_delta back in target language →
user listens via speaker → у будь-який момент будь-хто може заговорити
```

Це створює дві окремі задачі дизайну:

1. **"Хто є акторами?"** — UA людина, ES людина, і M (модель). M зараз майже невидимий у поточному UI. Як зробити його first-class entity? → Адресовано у варіантах 1–4.
2. **"Як показати real-time стан?"** — partial transcripts, M generating, audio playing back. Зараз цього взагалі немає у UI. → Адресовано у варіантах 5–8.

## Варіанти

### Текстові / turn-based (V1–V4)

Трактують Bridge як архів повідомлень. M отримує більше або менше уваги у різних варіантах. Не показують streaming state.

| # | Варіант | Ментальна модель | Density | Code | Drift |
|---|---------|------------------|---------|------|-------|
| 1 | [Triadic header + provenance](./01-triadic-header.md) | 3 актори locked зверху, провенанс на кожній картці | Medium | **Low** (~40 LOC) | Minor |
| 2 | [Pipeline rows](./02-pipeline-rows.md) | Кожен turn — Stripe-style dataflow pipe | Medium | Medium (~80 LOC) | Moderate |
| 3 | [Split channels](./03-split-channels.md) | Стенограф-вид, дві паралельні колонки | Medium-low | High (~120 LOC) | Major |
| 4 | [Transcript log](./04-transcript-log.md) | Editorial podcast / court transcript | **High** | Low (~50 LOC) | Moderate |

### Realtime-aware (V5–V8)

Кожен явно проектує streaming state як перший клас UI. Turn-картки (якщо є) стають архівом, а live state — головним фокусом.

| # | Варіант | Ментальна модель | Realtime feedback | Code | Drift |
|---|---------|------------------|-------------------|------|-------|
| 5 | [Жива тріада](./05-zhyva-tryada.md) (еволюція V1) | 3 капсули-актори з 4 станами кожна + live caption | Strong | High (~120 LOC) | Moderate |
| 6 | [Канали + живий шар](./06-kanaly-zhyvyj-shar.md) (еволюція V3) | Колонки V3 + partial transcripts streaming зверху + M dock з waveform | **Strongest** | Very high (~150 LOC) | Major |
| 7 | [Диригент](./07-dyryhent.md) | М як великий центр + анімовані dataflow dots між endpoints | Cinematic | Very high (~250 LOC) | Total rewrite |
| 8 | [Аудіо-ріки](./08-audio-riky.md) | Два waveform-стріми + rolling captions, без карток | Strongest + radical | Massive (~300 LOC) | Philosophical |

## Рекомендація

Ти сказав що тобі подобаються **V1** і **V3**. Логічна еволюція з urgent-приоритетом realtime:

- **Найбезпечніший вибір:** **V5 (Жива тріада)** — еволюція V1, додає realtime states без перебудови архітектури. Найкращий вибір якщо хочеш швидко зашипити.
- **Найсильніший вибір:** **V6 (Канали + Живий Шар)** — еволюція V3, додає partial-streams + реальний waveform. Найкраще передає stenographer-feel + дає всі realtime сигнали. Engineering-heavy, але справжній killer.
- **Найсміливіший:** **V8 (Аудіо-Ріки)** — заперечує chat-метафору повністю. Це або шедевр або помилка. Не для timeline-stressed періоду.
- **V7 (Диригент)** — найкращий для marketing. Не оптимальний для daily use.

### Гібриди варті розгляду

- **V5 cast row + V4 transcript body** — жива тріада зверху, дансий transcript внизу. Не потребує V3-style колонок. Дуже добрий баланс density + live state.
- **V6 колонки + V4 archive** — повний V6 але історичний archive під каналами форматується як V4 transcript-блоки, не як bubble-картки.

## Технічне питання — Soniox синхронізація

Ти запитав про Soniox sync. Контекст: на iOS Bridge ми НЕ використовуємо Soniox — він живе тільки у web mini-app через WebSocket. iOS все робить через `gpt-realtime` яка має built-in STT + audio out.

Але є цікавий **гібрид-варіант**: запустити Soniox **паралельно** виключно для відображення high-quality partial transcripts. Це актуально для V5, V6 і V8 де потрібен live caption text:

| Підхід | Pros | Cons |
|--------|------|------|
| Тільки gpt-realtime partials | Без додаткового cost, без зайвої складності | Партіали з'являються ПІСЛЯ VAD silence (~300-500ms лаг) |
| Soniox паралельно для UI | Per-word streaming, instant visual feedback | Дублювання audio stream, додатковий API cost |
| Hybrid: Soniox для UI, gpt-realtime для audio output | Найкращий UX + правильний audio | Найбільша складність, треба синхронізувати timestamps |

**Моя рекомендація:** почати з gpt-realtime-only партіалів. Якщо UX буде "слова з'являються повільно після того як я замовк" — тоді додати Soniox як upgrade за прапором `BridgeSettings.useHighFidelityCaptions = true`. Це уникає upfront over-engineering.

## Як вибирати

Прочитай **Ментальну модель** і **Що жертвується** у кожному файлі. Правильна відповідь залежить від того, що Bridge має робити у твоїй голові:

- "Це чат де перекладач допомагає" → **V1** або **V5**
- "Це pipeline який я спостерігаю" → **V2** або **V7**
- "Це транскрипт зустрічі" → **V3, V4, V6**
- "Це аудіо-стрім який я бачу" → **V8**

Скажи який (або яку комбінацію) — імплементую у SwiftUI на Bridge табі. Для V5–V8 ще обов'язково треба обговорити Soniox-питання перед стартом.
