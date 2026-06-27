# Безопасность мессенджера

## Архитектура защиты

```
Слой 1 — Transport      TLS 1.3 (Caddy автоматически)
Слой 2 — Auth           JWT (15 мин) + refresh rotation + rate limiting
Слой 3 — At-rest        AES-256-GCM: все сообщения в PostgreSQL зашифрованы
Слой 4 — E2EE           X25519 + AES-256-GCM: сервер видит только ciphertext
```

## Слой 3 — Server-side шифрование (как Telegram Cloud Chats)

Все сообщения шифруются `AES-256-GCM` ключом `MESSAGE_ENC_KEY`
до записи в PostgreSQL. Утечка базы данных без ключа — бессмысленный шифротекст.

```
Отправка:  plaintext → AES-256-GCM(key) → ciphertext → PostgreSQL
Чтение:    PostgreSQL → ciphertext → AES-256-GCM(key) → plaintext → клиент
```

## Слой 4 — E2EE (как Telegram Secret Chats / Signal)

```
Регистрация:
  Клиент генерирует X25519 keypair
  Public key  → сервер (хранит для других)
  Private key → только Keychain/Keystore устройства

Отправка:
  myPrivate + theirPublic → ECDH → sharedSecret (32 байта)
  plaintext + sharedSecret → AES-256-GCM → ciphertext
  ciphertext → сервер (хранит AS-IS, расшифровать не может)

Получение:
  myPrivate + senderPublic → ECDH → тот же sharedSecret
  ciphertext + sharedSecret → AES-256-GCM decrypt → plaintext
```

Сервер в любой момент видит только зашифрованный blob. Даже при полном
взломе сервера — содержимое E2EE переписки недоступно.

## Защита аутентификации

| Мера                      | Реализация                                    |
|---------------------------|-----------------------------------------------|
| Хеширование паролей       | bcrypt cost=12                                |
| Защита от brute-force     | Rate limit: 5 попыток/мин на IP               |
| JWT срок жизни            | Access: 15 мин, Refresh: 30 дней             |
| Refresh token rotation    | Одноразовый, хранится SHA-256 хешем           |
| Hashing refresh tokens    | `SHA-256(token)` в БД, не plaintext           |
| Logout everywhere         | Инвалидировать все refresh токены             |
| User enumeration          | Одинаковая ошибка для неверного email/пароля  |

## WebSocket

Токен передаётся в **первом WebSocket фрейме**, не в URL.

```
❌ ws://server/ws?token=eyJ...  ← попадает в nginx logs, Cloudflare logs
✅ ws://server/ws              ← подключение
   → {type: "auth", token: "eyJ..."} ← первый фрейм (не логируется)
```

## Security Headers

```
Strict-Transport-Security  max-age=63072000; includeSubDomains; preload
X-Frame-Options            DENY
X-Content-Type-Options     nosniff
Content-Security-Policy    default-src 'self'; connect-src 'self' wss:
Referrer-Policy            strict-origin-when-cross-origin
Permissions-Policy         geolocation=(), microphone=(), camera=()
```

## Что НЕ реализовано (расширения)

- **Double Ratchet** (Signal Protocol) — forward secrecy на уровне каждого сообщения
- **Sealed Sender** — скрыть метаданные отправителя
- **Disappearing messages** — автоудаление сообщений
- **Device verification** — QR-подтверждение identity
- **Push notifications** без раскрытия содержимого (как Signal)
