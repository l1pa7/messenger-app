# ⚡ Messenger

Красивый кроссплатформенный мессенджер с E2EE шифрованием.

**Stack:** Flutter · Go · PostgreSQL · Redis · MinIO · Caddy · Cloudflare Tunnel

## Скачать приложение

👉 **https://l1pa7.github.io/messenger-app**

Страница автоматически определит твоё устройство (Android / Windows / iPhone).

## Запустить сервер (одна команда)

### Linux / Ubuntu
```bash
git clone https://github.com/l1pa7/messenger-app.git
cd messenger-app
bash setup.sh
```

### Windows
```powershell
git clone https://github.com/l1pa7/messenger-app.git
cd messenger-app
powershell -ExecutionPolicy Bypass -File setup.ps1
```

Скрипт автоматически:
- Генерирует все пароли и ключи шифрования
- Создаёт файл `.env`
- Скачивает Docker-образы
- Запускает все сервисы
- Проверяет что всё работает

## Структура

```
backend/          Go API (Auth · Chat · File сервисы)
frontend/         Flutter приложение (iOS · Android · macOS · Windows)
docs/             Страница скачивания (GitHub Pages)
setup.sh          Автоустановка для Linux
setup.ps1         Автоустановка для Windows
docker-compose.yml
Caddyfile
SECURITY.md       Описание архитектуры безопасности
```

## API

| Метод | Путь | Описание |
|-------|------|----------|
| POST | /api/auth/register | Регистрация |
| POST | /api/auth/login | Вход |
| POST | /api/auth/refresh | Обновление токена |
| GET | /api/me | Текущий пользователь |
| GET | /api/chats | Список диалогов |
| POST | /api/chats | Создать диалог |
| GET | /api/chats/:id/messages | Сообщения |
| GET | /api/users/search?q= | Поиск пользователей |
| GET | /users/:id/key | Публичный E2EE ключ |
| WS | /ws | WebSocket (auth через первый фрейм) |

## Безопасность

Подробно: [SECURITY.md](SECURITY.md)

- 🔒 TLS 1.3 (Caddy)
- 🔑 bcrypt cost=12 для паролей
- ⏱️ Rate limiting: 5 попыток входа / мин
- 🗄️ AES-256-GCM шифрование сообщений в PostgreSQL
- 🔐 E2EE: X25519 + AES-256-GCM (ключи только на устройстве)
- 🔄 Refresh token rotation + SHA-256 хеширование
