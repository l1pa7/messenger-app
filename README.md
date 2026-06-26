# Messenger App

Красивый кроссплатформенный мессенджер.

**Stack:** Flutter (iOS · Android · macOS · Windows) + Go backend + PostgreSQL + Redis + MinIO + Caddy + Cloudflare Tunnel

## Быстрый старт (сервер)

```bash
# 1. Клонируй репо
git clone https://github.com/l1pa7/messenger-app.git
cd messenger-app

# 2. Настрой переменные окружения
cp .env.example .env
nano .env  # заполни пароли

# 3. Запусти
docker compose up -d

# 4. Проверь
curl http://localhost:8080/health
```

## Структура

```
backend/          Go API (Auth · Chat · File сервисы)
frontend/         Flutter приложение
docker-compose.yml
Caddyfile         Reverse proxy config
```

## API Endpoints

| Method | Path | Описание |
|--------|------|----------|
| POST | /api/auth/register | Регистрация |
| POST | /api/auth/login | Вход |
| GET | /api/me | Текущий пользователь |
| GET | /api/chats | Список диалогов |
| POST | /api/chats | Создать диалог |
| GET | /api/chats/:id/messages | Сообщения |
| GET | /api/users/search?q= | Поиск пользователей |
| WS | /ws | WebSocket соединение |

## WebSocket Protocol

```json
// Отправить сообщение
{ "type": "message", "payload": { "chat_id": 1, "content": "Привет!" } }

// Индикатор набора
{ "type": "typing", "payload": { "chat_id": 1 } }

// Получить (от сервера)
{ "type": "message", "payload": { ...message } }
{ "type": "typing", "payload": { "chat_id": 1, "user_id": 2 } }
{ "type": "online", "payload": { "user_id": 2, "online": true } }
```
