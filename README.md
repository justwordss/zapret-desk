# Zapret Desk

Приложение для macOS с интерфейсом управления стратегиями zapret и встроенным TG WS Proxy.

- Пакетная обработка IPv4 TCP и UDP.
- Выбор стратегии рядом с кнопкой включения.
- Импорт стратегий из BAT/TOML и по HTTPS-ссылке.
- Добавление доменов и исключений через приложение.
- Управление IP-листом стратегии.
- Отдельное переключение игрового фильтра: TCP, UDP или оба протокола.
- Встроенный Telegram-прокси.

## Установка

macOS 13+, Apple Silicon или Intel. Скачайте ZIP из **Releases**, распакуйте и перенесите **Zapret Desk.app** в «Программы». Для установки службы потребуется пароль администратора.

Тестовая сборка подписана ad-hoc, без нотариализации Apple. Если macOS блокирует доверенную копию, проверьте подпись и снимите карантин только с приложения:

```sh
codesign --verify --deep --strict "/Applications/Zapret Desk.app" &&
xattr -dr com.apple.quarantine "/Applications/Zapret Desk.app" &&
open "/Applications/Zapret Desk.app"
```

## Использование

Выберите стратегию на главном экране и включите обход. В разделе «Домены» добавляйте сайты и исключения. Импорт стратегий, IP-лист и управление службой находятся в настройках.

Для Telegram включите встроенный прокси и нажмите «Подключить Telegram». По умолчанию используется `127.0.0.1:1444`. Telegram-прокси работает, пока открыто приложение; служба обхода продолжает работать после закрытия окна.

## Сборка

Нужны macOS, Swift 6, Go 1.26+ и universal2 Python с python.org для упаковки Telegram-прокси. Конечному пользователю Python не требуется.

```sh
./scripts/build.sh
```

Результат: `dist/Zapret Desk.app` и `dist/ZapretDesk-macOS.zip`. Скрипт поддерживает переменные `GO_BINARY`, `PYTHON_BINARY`, `BUILD_DIR`, `GOPATH`, `TELEGRAM_RUNTIME`.

## Основы и лицензии

Использованы [zapret](https://github.com/bol-van/zapret), [zapret-for-mac](https://github.com/naladwepo/zapret-for-mac), [стратегии Flowseal](https://github.com/Flowseal/zapret-discord-youtube) и [TG WS Proxy](https://github.com/Flowseal/tg-ws-proxy).

Лицензии и уведомления об авторских правах сохранены в `LICENSE`, `backend/LICENSE`, `telegram/LICENSE` и `ThirdParty/`.
