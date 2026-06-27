#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup.sh — одна команда запускает весь мессенджер
# Использование: bash setup.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# Цвета для вывода
R='\033[0;31m' G='\033[0;32m' B='\033[0;34m' Y='\033[1;33m' N='\033[0m'
BOLD='\033[1m'

header() { echo -e "\n${B}${BOLD}$1${N}"; }
ok()     { echo -e "  ${G}✓${N}  $1"; }
info()   { echo -e "  ${B}→${N}  $1"; }
warn()   { echo -e "  ${Y}!${N}  $1"; }
fail()   { echo -e "  ${R}✗${N}  $1"; exit 1; }

echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${BOLD}  ⚡ Messenger — автоматическая установка${N}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"

# ── Проверка зависимостей ─────────────────────────────────────────────────────
header "Проверка зависимостей"

command -v docker   >/dev/null 2>&1 || fail "Docker не установлен. Установи: https://docs.docker.com/engine/install/ubuntu/"
command -v openssl  >/dev/null 2>&1 || fail "openssl не найден (sudo apt install openssl)"
ok "Docker найден: $(docker --version | cut -d' ' -f3 | tr -d ',')"
ok "openssl найден"

# ── Генерация .env ────────────────────────────────────────────────────────────
header "Настройка конфигурации"

if [ -f .env ]; then
  warn "Файл .env уже существует — пропускаю генерацию (удали его для пересоздания)"
else
  info "Генерирую случайные пароли через openssl rand..."

  # Каждый openssl rand -hex N генерирует N*2 случайных символов
  DB_PASS=$(openssl rand -hex 20)       # пароль к PostgreSQL
  REDIS_PASS=$(openssl rand -hex 20)    # пароль к Redis
  MINIO_PASS=$(openssl rand -hex 20)    # пароль к MinIO
  JWT_KEY=$(openssl rand -hex 32)       # ключ подписи JWT-токенов (64 символа)
  ENC_KEY=$(openssl rand -hex 32)       # ключ шифрования сообщений в БД (64 символа)

  cat > .env << EOF
# ─────────────────────────────────────────────────────────────────────────────
# .env — автоматически создан setup.sh
# Не коммить этот файл в git (он уже в .gitignore)
# ─────────────────────────────────────────────────────────────────────────────

# PostgreSQL — база данных
# Хранит: пользователей, диалоги, сообщения (зашифрованные)
DB_USER=messenger
DB_PASSWORD=${DB_PASS}
DB_NAME=messenger

# Redis — быстрый кеш в памяти
# Хранит: кто сейчас онлайн, сессии, очереди сообщений
REDIS_PASSWORD=${REDIS_PASS}

# MinIO — хранилище файлов (аналог Amazon S3, но свой)
# Хранит: фотографии, видео, аватарки пользователей
MINIO_USER=minioadmin
MINIO_PASSWORD=${MINIO_PASS}
MINIO_BUCKET=messenger-files

# JWT_SECRET — секретный ключ для подписи токенов авторизации
# Токены — это то, что подтверждает "ты вошёл в аккаунт"
# Если этот ключ утечёт — можно подделать любой токен → украсть любой аккаунт
# Поэтому генерируем случайные 64 символа
JWT_SECRET=${JWT_KEY}

# MESSAGE_ENC_KEY — ключ шифрования AES-256-GCM
# Всё что хранится в PostgreSQL — зашифровано этим ключом
# Даже если украдут базу данных — без этого ключа прочитать ничего нельзя
# ВАЖНО: храни отдельно от бэкапов базы!
MESSAGE_ENC_KEY=${ENC_KEY}

# ALLOWED_ORIGINS — с каких сайтов разрешено подключение к API (CORS)
# После настройки Cloudflare Tunnel замени на свой домен
# Пример: ALLOWED_ORIGINS=https://messenger.example.com
ALLOWED_ORIGINS=http://localhost
EOF

  ok ".env создан — пароли сгенерированы автоматически"
fi

# ── Запуск Docker Compose ─────────────────────────────────────────────────────
header "Запуск контейнеров"

info "Скачиваю образы и запускаю..."
docker compose pull --quiet
docker compose up -d

# Ждём пока всё поднимется
info "Жду запуска (15 сек)..."
sleep 15

# ── Проверка здоровья ─────────────────────────────────────────────────────────
header "Проверка"

# PostgreSQL
if docker compose exec -T postgres pg_isready -U messenger -q 2>/dev/null; then
  ok "PostgreSQL работает"
else
  warn "PostgreSQL ещё стартует — подожди минуту"
fi

# Redis
if docker compose exec -T redis redis-cli -a "$(grep REDIS_PASSWORD .env | cut -d= -f2)" ping 2>/dev/null | grep -q PONG; then
  ok "Redis работает"
else
  warn "Redis ещё стартует"
fi

# Backend API
if curl -sf http://localhost:8080/health >/dev/null 2>&1; then
  ok "Backend API работает → http://localhost:8080"
else
  warn "Backend ещё стартует — это нормально, подожди 30 сек"
  info "Проверить вручную: curl http://localhost:8080/health"
fi

# MinIO
if curl -sf http://localhost:9000/minio/health/live >/dev/null 2>&1; then
  ok "MinIO работает → http://localhost:9001 (веб-панель)"
fi

# ── Итог ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${G}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${G}${BOLD}  ✅ Мессенджер запущен!${N}"
echo -e "${G}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""
echo -e "  ${BOLD}API бэкенд:${N}     http://localhost:8080"
echo -e "  ${BOLD}MinIO панель:${N}   http://localhost:9001"
echo -e "  ${BOLD}Логи:${N}           docker compose logs -f"
echo ""
echo -e "  ${Y}Следующий шаг:${N} настроить Cloudflare Tunnel"
echo -e "  Гайд: https://github.com/l1pa7/messenger-app#tunnel"
echo ""
