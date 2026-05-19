# 07 — Стан розробки

Поточний статус проєкту, що готове, що в роботі, що далі.

---

## Що вже працює

### Telegram бот (production)
- Деплой автоматичний через GitHub Actions при пуші в `main`.
- Кожен push → SSH на Hetzner → git pull → npm install → PM2 restart.
- Domain: `https://89-167-19-222.sslip.io` (прода), `https://<ngrok>.ngrok.app` (DEV).
- Приймає голосові повідомлення українською/іспанською/англ/рос/груз/угор/індонез.
- Розуміє команди `/start`, `/voice`, `/settings`, `/stats`.
- MongoDB Docker container зберігає юзерів і їхні налаштування.
- ~50 активних alpha-юзерів з Telegram.

### Telegram Mini App (production)
- Чотири табu: Voice, Live, Realtime, Chat.
- Live tab — найбагатший pipeline (Soniox + Groq + ElevenLabs streaming).
- Realtime + Chat tabs — WebRTC напряму до OpenAI.
- Cost guard з 8 тригерами (включаючи Telegram MainButton).
- Авторизація через `Telegram.WebApp.initDataUnsafe.user.id`.
- Переключення між Soniox/ElevenLabs STT і Gemini/Groq translation за конфігом.

### iOS native app (готовий до тестування)
- Три таби: Voice (Soniox+Groq+ElevenLabs live pipeline), Realtime (gpt-realtime-translate), Chat (gpt-realtime conversational).
- Sign in with Apple → JWT → стандартні API запити.
- Cost guard з 7 тригерами (включаючи iOS-специфічні lifecycle events).
- 52 Swift файли, 3.7K LoC, **64 unit-тести проходять**.
- Збирається через xcodegen, deploys в iPhone simulator.
- Beige theme `#F5F0EB` mirror Telegram Mini App.
- Tab switch → одразу stop активної сесії (як cost guard).

### Backend
- Node.js + Express 5, ~700 LoC у `src/server.js`.
- Endpoints: `/api/realtime/session`, `/api/realtime-chat/session`, `/api/translate-auto`, `/api/tts`, `/api/voice/transcribe`, `/api/auth/apple`, `/api/user/me`.
- WebSocket proxy `/ws/live` для Mini App Live tab.
- JWT middleware з `jose` для Apple Sign In.
- Telegraf bot framework + audioHandler для voice messages.

---

## Що в роботі / нещодавні зміни

| Дата | Що зроблено |
|---|---|
| 2026-05-08 | iOS app v0.1: 3 tabs, Apple Sign In, cost guard, 64 unit-tests, Live Voice pipeline |
| 2026-05-08 | Mini App: Live tab з Soniox+Groq+ElevenLabs streaming |
| 2026-05-08 | Backend: `/api/auth/apple` + JWT middleware + User.appleSub |
| 2026-05-04 | Bot: dev:ngrok script для локального тестування Mini App |

---

## Стратегічне рішення 2026-05-08

**Telegram бот + Mini App видаляються.** Єдина цільова платформа — iOS native app. Деталі у [04-platforms.md](04-platforms.md#стратегія-розповсюдження-оновлена).

План:
1. iOS додаток → TestFlight → App Store public.
2. Telegram бот: додати редирект-повідомлення → потім вимкнути.
3. Backend: видалити Telegraf, audioHandler, webapp/, /api/user/{telegramId}. Залишити тільки iOS API.

Решта документу (нижче) описує інкрементальний роадмап для **iOS-only** реальності.

---

## Що далі (roadmap)

### Короткостроково (2-4 тижні)
- [ ] **App Store TestFlight** — потребує Apple Developer Program $99/рік + signing certificate + beta testers.
- [ ] **Lock-screen control** — `MPRemoteCommandCenter` для пауза/продовження з лок-екрана.
- [ ] **Українська як target в Realtime** — чекаємо коли OpenAI додасть синтез української в `gpt-realtime-translate` (поки фолбекаємо на російську).
- [ ] **Live debounced TTS у Voice tab iOS** — зараз одношотний на фінал; портувати streaming TTS з Mini App `/ws/live`.

### Середньостроково (1-3 місяці)
- [ ] **Платіжна інтеграція** (App Store IAP) — для тестування премиум tier.
- [ ] **Synced settings через iCloud** — налаштування слідують за юзером між пристроями.
- [ ] **Translation history** — список останніх перекладів, можливість повернутись/поділитись.
- [ ] **Push notifications** — нагадування про продовження сесії, оновлення.
- [ ] **Apple Watch app** — спрощений Voice tab для швидких перекладів з годинника.
- [ ] **Українізація UI** — повний переклад інтерфейсу iOS app, Localizable.xcstrings.
- [ ] **Anti-abuse rate limiting** — Cloudflare або Express middleware на endpoints.

### Довгостроково (3-6 місяців)
- [ ] **Android app** — Kotlin Multiplatform або React Native?
- [ ] **Веб-версія** — окремий від Mini App standalone PWA.
- [ ] **B2B API** — окремий tier для готелів, клінік.
- [ ] **CarPlay підтримка** — Voice tab у машині.
- [ ] **Speaker diarization** — у Chat tab розділяти «хто 1» / «хто 2», показувати правильно.
- [ ] **Custom voice cloning** — навчити модель твого голосу для TTS.
- [ ] **Translation memory** — запам'ятовувати твої унікальні слова/терміни (наприклад фахові).

---

## Відкриті стратегічні питання

### 1. Бізнес-модель
- Free + Premium subscription? Чи one-time purchase? Чи pay-per-minute?
- Поки що автор покриває з кишені — не масштабується після ~100 активних юзерів.

### 2. Маркетинг
- Як знайти першу 1000 юзерів? Через українські Telegram-канали для мігрантів? Через Reddit r/Spain, r/Germany expat-сабреддіти? Через Product Hunt запуск?
- Поки немає бренда, лендингу, скріншотів готових для App Store.

### 3. Підтримка
- Хто відповідає юзерам коли щось не працює? Поки автор сам у Telegram. Не масштабується.
- Потрібен FAQ + support email + tracking з Sentry.

### 4. Privacy і compliance
- Аудіо проходить через OpenAI/Soniox/ElevenLabs — у нас не зберігається, але вони можуть використовувати для тренування своїх моделей.
- Для B2B (медицина, юристи) це блокер — потрібен HIPAA/GDPR-friendly stack.
- Currently: ToS + Privacy Policy ще не написані.

### 5. Команда
- Поки 1 розробник + Claude як co-pilot.
- Для App Store launch потрібен: дизайнер (App Store screenshots, app icon), QA-тестер, маркетинг-людина.

---

## Тестове покриття

iOS app:

| Suite | Тестів | Що покриває |
|---|---|---|
| RealtimeEventDecoderTests | 18 | Усі типи OpenAI events + fallback на `.other` + edge cases |
| CostGuardTests | 10 | Start, stop, extend (+2 from existing), deadline auto-stop, warn fires before stop, idempotency, manual reason |
| APIClientTests | 7 | Mock URLProtocol — успіх/помилка/декодування/JWT injection/JSON shapes |
| ChatSettingsTests | 7 | UserDefaults persistence для voice/lang/VAD/instructions, reset до default |
| AuthStoreTests | 6 | Sign in/out lifecycle, Apple request encoding, response decoding |
| TargetLanguagesTests | 7 | 13 supported codes, відсутність UA, стабільність ID |
| DiagLoggerTests | 5 | Ring buffer 500 cap, теги, snapshot, clear |
| VoiceLanguagesTests | 4 | 7 supported codes mirror Mini App dropdown |
| **Разом** | **64** | **0 failures** |

Backend наразі без unit-тестів — це борг. Заплановано в наступному спринті.

---

## Ризики

1. **OpenAI ціна може зрости** — Realtime API дороге, ціна може ↑ на 50-100% при попиті. Спустить comfort-margin.
2. **Apple App Review** — Sign in with Apple і записи мікрофона можуть викликати запити на додатковий justify від Apple. Перший reject можливий.
3. **Telegram policy зміни** — Bot API чи Mini App обмеження можуть приходити внезапно.
4. **Конкурент від Apple/Google** — iOS 18 додав native Translation framework. Якщо вони зроблять realtime у системній app — ми втрачаємо unique selling point.
5. **Нерентабельність** — якщо 80% юзерів використовує Realtime/Chat на $30/місяць а платять $5, ми втрачаємо. Треба правильні ліміти у free tier.
