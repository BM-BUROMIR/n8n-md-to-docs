# Deployment Guide - md2doc-converter

## Quick Start (Docker)

### 1. Build and Run

```bash
docker-compose up --build -d
```

Сервис будет доступен на: `http://localhost:8080`

### 2. Проверка работоспособности

```bash
curl http://localhost:8080/health
```

Ответ должен быть: `{"status":"ok","service":"md2doc-converter"}`

### 3. Тестовый запрос с формулами

```bash
curl -X POST http://localhost:8080/ \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_N8N_GOOGLE_OAUTH_TOKEN" \
  -d '{
    "output": "# Test Document\n\n## Formula Test\n\nSimple: $x + y = z$\n\nComplex: $V = \\sum_{t=1}^{n} \\frac{ЧДП_t}{(1+r)^t}$",
    "fileName": "Test with Formulas"
  }'
```

### 4. Остановка

```bash
docker-compose down
```

## Получение OAuth токена из n8n

В вашем n8n workflow:

1. Используйте HTTP Request node
2. Authentication: Google OAuth2
3. Токен автоматически добавится в заголовок Authorization

## Logs

```bash
docker-compose logs -f md2doc-converter
```

## Порты

- **8080** - HTTP API endpoint

## Environment Variables

- `PORT` - Порт сервера (default: 8080)
- `NODE_ENV` - Окружение (production/development)

## Health Check

Автоматическая проверка здоровья контейнера каждые 30 секунд:
- URL: `http://localhost:8080/health`
- Timeout: 10s
- Retries: 3

## Tunnel (serveo.net) для внешнего доступа

Для временного доступа извне через SSH туннель:

```bash
# Запуск туннеля (с уникальным alias)
./start-tunnel.sh md2doc

# Или с дефолтным alias
./start-tunnel.sh
```

Скрипт автоматически:
1. Проверит, что контейнер запущен
2. Проверит health endpoint
3. Создаст SSH туннель через serveo.net
4. Покажет публичный URL (например: `https://md2doc.serveo.net`)
5. Выведет тестовые команды для проверки

Для остановки туннеля:
- Нажмите `Ctrl+C` в терминале со скриптом
- Или запустите: `./stop-tunnel.sh`

**Важно:** Туннель serveo.net предназначен для тестирования. Для продакшена используйте nginx/traefik с SSL.

## Production Deployment

Для деплоя на сервере:

1. Скопируйте проект на сервер
2. Запустите: `docker-compose up -d`
3. Настройте nginx/traefik для проксирования на порт 8080
4. Добавьте SSL сертификат

### Пример nginx config:

```nginx
server {
    listen 80;
    server_name md2doc.yourdomain.com;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```
