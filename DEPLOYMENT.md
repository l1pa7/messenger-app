# Гайд по установке сервера

## Что происходит на экране сейчас (установка Ubuntu 24.04)

Когда установщик спросит — выбирай:
- **Язык**: English (стабильнее для серверного ПО)
- **Имя сервера**: `messenger` (или любое)
- **Имя пользователя**: любое, запомни
- **Пароль**: надёжный, запомни
- **OpenSSH server**: ✅ установить (чтобы управлять с другого компа)
- **Дополнительные пакеты**: ничего не выбирай

---

## Фаза 1 — Первый вход (сразу после установки)

```bash
# Обновить систему
sudo apt update && sudo apt upgrade -y

# Установить нужные утилиты
sudo apt install -y curl wget git ufw

# Настроить файрвол
sudo ufw allow ssh      # управление по SSH
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS
sudo ufw --force enable

# Проверить
sudo ufw status
```

---

## Фаза 2 — Установка Docker (одна команда)

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker          # применить без перезагрузки

# Проверка
docker run hello-world
```

---

## Фаза 3 — Клонировать репо и запустить

```bash
git clone https://github.com/l1pa7/messenger-app.git
cd messenger-app
bash setup.sh
```

Скрипт сам сгенерирует все пароли, запустит PostgreSQL, Redis, MinIO и Go-бэкенд.

Проверить что всё работает:
```bash
curl http://localhost:8080/health
# должен вернуть: {"status":"ok"}

docker compose ps
# все контейнеры должны быть Up
```

---

## Фаза 4 — Cloudflare Tunnel (интернет без белого IP)

### 4.1 Зарегистрируйся на cloudflare.com

Бесплатный аккаунт. Домен не обязателен — дадут бесплатный `*.trycloudflare.com`.

### 4.2 Установить cloudflared на сервер

```bash
curl -L \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
  -o cloudflared.deb
sudo dpkg -i cloudflared.deb
cloudflared --version   # проверка
```

### 4.3 Вариант А — Быстрый тест (временный URL, без аккаунта)

```bash
cloudflared tunnel --url http://localhost:80
```

Выдаст URL вида `https://abc-random.trycloudflare.com` — уже можно подключаться!
Работает пока терминал открыт. Для постоянной работы — вариант Б.

### 4.4 Вариант Б — Постоянный туннель (рекомендуется)

```bash
# Авторизация (откроет ссылку — открой на основном компе)
cloudflared tunnel login

# Создать туннель
cloudflared tunnel create messenger

# Посмотреть ID туннеля
cloudflared tunnel list

# Создать конфиг (замени TUNNEL_ID на свой)
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml << EOF
tunnel: TUNNEL_ID
credentials-file: /root/.cloudflared/TUNNEL_ID.json

ingress:
  - service: http://localhost:80
EOF

# Запустить как системный сервис (работает всегда, даже после перезагрузки)
sudo cloudflared service install
sudo systemctl enable --now cloudflared
sudo systemctl status cloudflared
```

### 4.5 Обновить домен в настройках

```bash
cd ~/messenger-app
# Открыть .env и заменить ALLOWED_ORIGINS
sed -i 's|ALLOWED_ORIGINS=.*|ALLOWED_ORIGINS=https://ТВОй-ДОМЕН.trycloudflare.com|' .env
docker compose restart backend
```

---

## Управление сервером

```bash
# Логи в реальном времени
docker compose logs -f

# Логи конкретного сервиса
docker compose logs -f backend

# Перезапустить всё
docker compose restart

# Остановить
docker compose down

# Обновить до новой версии
git pull
docker compose up -d --build
```

---

## Если сервер перезагрузился

Docker Compose настроен с `restart: unless-stopped` — все контейнеры
стартуют автоматически при включении ноутбука. Делать ничего не нужно.

---

## Ресурсы ноутбука-сервера

Минимальные требования для комфортной работы:
- **RAM**: 2 GB (PostgreSQL ~200MB, Redis ~50MB, Go ~30MB, MinIO ~100MB)
- **Диск**: 10 GB свободного места
- **CPU**: любой, даже i3 справится
