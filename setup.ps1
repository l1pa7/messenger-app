# setup.ps1 — установка на Windows (до того как поставишь Ubuntu на ноутбук)
# Запуск: правый клик → "Выполнить с помощью PowerShell"
# Или в терминале: powershell -ExecutionPolicy Bypass -File setup.ps1

param([switch]$Reset)

function Write-Header($text) { Write-Host "`n$text" -ForegroundColor Blue }
function Write-Ok($text)     { Write-Host "  ✓  $text" -ForegroundColor Green }
function Write-Info($text)   { Write-Host "  →  $text" -ForegroundColor Cyan }
function Write-Warn($text)   { Write-Host "  !  $text" -ForegroundColor Yellow }
function Write-Fail($text)   { Write-Host "  ✗  $text" -ForegroundColor Red; exit 1 }

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue
Write-Host "  ⚡ Messenger — автоматическая установка" -ForegroundColor Blue
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Blue

# Проверка Docker
Write-Header "Проверка зависимостей"
try {
    $v = docker --version
    Write-Ok "Docker найден: $v"
} catch {
    Write-Fail "Docker не установлен. Скачай: https://www.docker.com/products/docker-desktop/"
}

# Генерация случайной строки
function New-Secret([int]$bytes = 20) {
    $arr = New-Object byte[] $bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($arr)
    return ($arr | ForEach-Object { $_.ToString("x2") }) -join ""
}

# Генерация .env
Write-Header "Настройка конфигурации"

if ((Test-Path ".env") -and -not $Reset) {
    Write-Warn "Файл .env уже существует — пропускаю (запусти с -Reset для пересоздания)"
} else {
    Write-Info "Генерирую случайные пароли..."

    $dbPass    = New-Secret 20
    $redisPass = New-Secret 20
    $minioPass = New-Secret 20
    $jwtKey    = New-Secret 32
    $encKey    = New-Secret 32

    @"
# .env — автоматически создан setup.ps1

# PostgreSQL — база данных (пользователи, диалоги, сообщения)
DB_USER=messenger
DB_PASSWORD=$dbPass
DB_NAME=messenger

# Redis — кеш (онлайн-статус, сессии)
REDIS_PASSWORD=$redisPass

# MinIO — хранилище файлов (фото, видео, аватарки)
MINIO_USER=minioadmin
MINIO_PASSWORD=$minioPass
MINIO_BUCKET=messenger-files

# JWT — ключ подписи токенов авторизации
JWT_SECRET=$jwtKey

# AES-256-GCM — ключ шифрования сообщений в базе данных
MESSAGE_ENC_KEY=$encKey

# CORS — разрешённые домены (поменяй после настройки Cloudflare)
ALLOWED_ORIGINS=http://localhost
"@ | Out-File -FilePath ".env" -Encoding UTF8

    Write-Ok ".env создан — пароли сгенерированы автоматически"
}

# Запуск
Write-Header "Запуск контейнеров"
Write-Info "Скачиваю образы (первый раз может занять несколько минут)..."

docker compose pull
docker compose up -d

Write-Info "Жду запуска (15 сек)..."
Start-Sleep -Seconds 15

# Проверка
Write-Header "Проверка"

try {
    $resp = Invoke-WebRequest -Uri "http://localhost:8080/health" -TimeoutSec 5 -UseBasicParsing
    if ($resp.StatusCode -eq 200) { Write-Ok "Backend API работает" }
} catch {
    Write-Warn "Backend ещё стартует — подожди 30 сек и проверь: http://localhost:8080/health"
}

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host "  ✅ Мессенджер запущен!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
Write-Host ""
Write-Host "  API бэкенд:   http://localhost:8080" -ForegroundColor White
Write-Host "  MinIO панель: http://localhost:9001" -ForegroundColor White
Write-Host "  Логи:         docker compose logs -f" -ForegroundColor White
Write-Host ""
Write-Host "  Следующий шаг: настроить Cloudflare Tunnel" -ForegroundColor Yellow
Write-Host ""
