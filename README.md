# KUpergram — приватный форк Telegram iOS (для двух человек)

Обычный Telegram-функционал берётся из официального открытого форка
[`Telegram-iOS`](https://github.com/TelegramMessenger/Telegram-iOS). Поверх него
добавляется раздел **KUpergram** с визуальной экономикой: внутренние Stars,
коллекция NFT-карточек, магазин, дарение и админ-панель.

> ⚠️ **Важно.** Внутренние Stars и NFT — **косметические сущности этого форка**.
> Это НЕ настоящие Telegram Stars и НЕ блокчейн-NFT. Они существуют только внутри
> приложения двух пользователей и не выдаются за подтверждённые активы Telegram.

## Структура

```
KUpergram/
├── server/                     # бэкенд синхронизации (FastAPI + SQLite) — ПРОТЕСТИРОВАН
│   ├── main.py
│   └── requirements.txt
├── ios-extras/                 # Swift-модуль, встраивается в форк
│   ├── Package.swift
│   └── Sources/KUpergramExtras/
│       ├── Models.swift            # модели (Codable, маппинг на snake_case сервера)
│       ├── KUpergramAPI.swift      # сетевой клиент (все эндпоинты, Idempotency-Key)
│       ├── KUpergramStore.swift    # единое состояние + локальный кэш + синк + анти-дабл-тап
│       ├── UIKit+Theme.swift       # тема, карточки, баннер ошибок, бейдж «визуальный»
│       ├── StarsView.swift         # баланс + история
│       ├── GiftsView.swift         # сетка коллекции
│       ├── GiftDetailView.swift    # детали + «Подарить» + «Апгрейд»
│       ├── ShopView.swift          # магазин за Stars (вкл. бесплатные)
│       ├── GiftHistoryView.swift   # «Подарил / Получил»
│       ├── AdminPanelView.swift    # add by slug / edit / delete / баланс / передача
│       ├── GiftAnimation.swift     # анимация передачи + конфетти (чистый SwiftUI)
│       └── KUpergramRootView.swift # TabView + мост KUpergramHost → UIHostingController
└── .github/workflows/
    ├── extras-check.yml        # дешёвая сборка Swift-модуля под iOS (реальная проверка)
    └── telegram-ipa.yml        # тяжёлая сборка форка в .ipa (ручная, каркас)
```

## Статус проверки

- **Сервер** — прогнан функциональный тест всего флоу (покупка за 0 и за звёзды,
  апгрейд, дарение со сменой владельца, проверка владельца на сервере, защита от
  овердрафта, идемпотентность против двойного списания). ✅
- **Swift-модуль** — написан и вычитан; компиляция проверяется в CI
  (`extras-check.yml`) на macOS-раннере, т.к. на Windows нет Swift-тулчейна.

## Сервер: запуск

```bash
cd server
pip install -r requirements.txt
ADMIN_TOKEN='<длинный-секрет>' python -m uvicorn main:app --host 0.0.0.0 --port 8099
```

Два пользователя (`me`, `friend`) создаются автоматически. Клиент на каждом
iPhone настраивается на свой `currentUserId`.

## Встраивание в форк

В коде форка, где добавляешь пункт меню/раздел, открывай:

```swift
import KUpergramExtras

let vc = KUpergramHost.makeViewController(
    baseURL: URL(string: "https://<твой-сервер>")!,
    adminToken: keychain.adminToken,   // хранить в Keychain, НЕ в исходниках
    currentUserId: "me"                // или "friend"
)
navigationController?.pushViewController(vc, animated: true)
```

## Маршрут сборки (без покупки Mac)

1. Приватный репозиторий на GitHub.
2. `extras-check.yml` — убеждаемся, что Swift-модуль собирается.
3. `telegram-ipa.yml` (вручную) — собираем unsigned `.ipa` форка. **Самый хрупкий
   шаг**: Bazel, большие ресурсы, лимит macOS-минут ×10. Довести можно только
   итеративно на реальных прогонах.
4. `api_id`/`api_hash` с [my.telegram.org](https://my.telegram.org) — в
   **Secrets репозитория**, не в коде.
5. Установка `.ipa` через **AltStore** (подпись бесплатным Apple ID, переподпись
   каждые 7 дней, лимит 3 sideload-приложения).
```
