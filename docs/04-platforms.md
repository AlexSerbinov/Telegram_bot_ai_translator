# 04 — Платформи

> **⚠️ Стратегічна замітка (2026-05-08):** Цільова платформа продукту — iOS native app. Telegram-формати (бот + Mini App) описані тут для повноти, але **видаляються** найближчим часом. Розділи 1 і 2 нижче — історичний контекст (звідки виник продукт). Розділ 3 — куди йде продукт.

Teycan Translate історично існував у трьох форматах. Сьогодні залишається тільки iOS native — Telegram-формати плануються до видалення.

---

## 1. Telegram бот *(legacy — буде видалено)*

**Назва в Telegram:** `@teycan_translate_bot` (production), `@teycan_translate_dev_bot` (DEV).

**Як юзер взаємодіє:**
- Просто додає бота в чат, надсилає голосове повідомлення → бот відповідає текстом перекладу + озвучкою.
- Може налаштувати пару мов через `/settings`.
- Команди: `/start`, `/voice`, `/settings`, `/stats`, `/help`.

**Кому підходить:**
- Тим, хто не хоче нічого ставити на телефон.
- Тим, хто хоче обмінюватись перекладами в чаті — пересилати голосові, ділитись.
- Тим, хто живе в Telegram (мільйони українців і росіян).

**Обмеження:**
- Тільки одношотний переклад (записав → отримав).
- Без живого синхронного режиму.
- Залежить від того, що Telegram дозволяє ботам.

---

## 2. Telegram Mini App *(legacy — буде видалено)*

**Що це:** Веб-додаток у вигляді WebView всередині Telegram, відкривається через кнопку у боті.

**Як юзер взаємодіє:**
- Тапає кнопку в боті — відкривається повноцінний UI з 4 табами:
  - Voice — як у боті, але з кращою візуалізацією.
  - Live — Soniox + Groq + ElevenLabs streaming pipeline (живий переклад з малою затримкою).
  - Realtime — OpenAI gpt-realtime-translate (синхронний переклад).
  - Chat — OpenAI gpt-realtime двосторонній.

**Кому підходить:**
- Тим, хто вже в Telegram і хоче більше функцій ніж бот, але не хоче ставити окремий додаток.
- Усі функції доступні без скачування — швидкий доступ.
- Авторизація через Telegram (initData) — без окремого логіну.

**Обмеження:**
- WebView має деякі особливості з мікрофоном (іноді гірша якість запису ніж native).
- Залежить від поведінки Telegram-клієнта (особливо на iOS — кеш WebView).
- Не підтримує App Store distribution.

**Технологічно:** Express server + HTML/CSS/JS у `src/webapp/index.html`. Розгорнуто на `https://89-167-19-222.sslip.io` (Hetzner).

---

## 3. iOS Native Swift App - залишається тільки цей. телеграм ми видаляємо. 

**Що це:** Повноцінний native iOS додаток на SwiftUI, оптимізований під iPhone.

**Як юзер взаємодіє:**
- Скачує з App Store (планується), відкриває.
- Логиниться через **Sign in with Apple** (один тап + Touch/Face ID).
- Бачить три таби: Voice, Realtime, Chat (Live tab свідомо не портовано — Realtime + Chat покривають той самий use case).

**Що краще ніж Mini App:**
- **Кращий мікрофон** — без WebView обмежень, прямий доступ до AVAudioEngine.
- **Якісне аудіо** — нативний AVAudioPlayer без затримки декодування.
- **Lock-screen control** — sесію можна паузити з лок-екрана / Control Center (через MPRemoteCommandCenter).
- **Реальний lifecycle** — коли юзер залишає app, ми точно знаємо це і одразу зупиняємо WebRTC (cost guard).
- **Bluetooth / AirPods** — нативна підтримка маршрутизації звуку.
- **Push notifications** (плануються) — нагадування про продовження сесії.

**Sign in with Apple:**
- Apple ID користувача = primary key у нашій базі.
- Налаштування (мови, голос, промт) синкаються між пристроями.
- Окремий JWT (30 днів) — після першого логіну юзер не бачить екрану входу довго.

**Технологічно:**
- Стек: SwiftUI + Observation framework (iOS 17+), WebRTC через SwiftPM (`stasel/WebRTC`), Soniox WS через `URLSessionWebSocketTask`, Apple auth через `AuthenticationServices`.
- Cost guard зі всіма 7-ма тригерами зупинки.
- 64 unit tests покривають event decoder, cost guard, API client, mock-WS, language metadata.
- Знаходиться в `ios/TeycanTranslate/` гіт-репозиторію.

---

## Порівняння

| Функція | TG бот | Mini App | iOS native |
|---|---|---|---|
| Voice (одношотний) | ✅ | ✅ | ✅ |
| Live (Soniox+Groq+EL stream) | ❌ | ✅ | ✅ (як Voice tab) |
| Realtime (gpt-realtime-translate) | ❌ | ✅ | ✅ |
| Chat (gpt-realtime conversational) | ❌ | ✅ | ✅ |
| Edit system prompt | ❌ | ✅ | ✅ |
| Sign in with Apple | ❌ | ❌ | ✅ |
| Lock-screen Stop | ❌ | ❌ | ✅ (плануються) |
| Bluetooth audio | ⚠️ | ⚠️ | ✅ |
| Cost guard з автозупинкою | ❌ | ✅ | ✅ |
| App Store distribution | — | — | ✅ (плануються) |
| Без скачування | ✅ | ✅ | ❌ |

---

## Стратегія розповсюдження (оновлена)

**Єдина платформа на майбутнє** — iOS native app з distribution через App Store. Telegram-формати були prototype-стадією для швидкого тестування ідеї і отримання перших юзерів — їхня роль виконана.

**План migration:**
1. iOS app публікується на App Store (TestFlight → public).
2. У Telegram-боті додається повідомлення «продукт переїхав в App Store, ось посилання».
3. Через ~1-2 місяці після iOS-релізу — Telegram бот і Mini App вимикаються.
4. Backend очищається від Telegram-специфічного коду (Telegraf framework, audioHandler.js, Mini App webapp/, attachLiveWs, /api/user/{telegramId}). Залишається тільки iOS-orientований API: `/api/auth/apple`, `/api/user/me`, `/api/realtime/session`, `/api/realtime-chat/session`, `/api/voice/transcribe`, `/api/translate-auto`, `/api/tts`.

**Чому iOS-only:**
- Якісніший мікрофон і аудіо-стек.
- Sign in with Apple усуває friction реєстрації.
- App Store даровний distribution-channel + платіжна інтеграція через IAP.
- Можна сфокусувати ресурси на одній платформі замість підтримувати три.
- Telegram-обмеження на bots (audio file size, response timeout, WebView quirks) знімаються.

**Що буде з юзерами Telegram-боту?** Якщо створимо мапінг `telegramId → appleSub` (через email чи спільну реєстрацію), вони зможуть перенести налаштування. Інакше — нова реєстрація через Apple ID. Поки рішення не прийнято.
