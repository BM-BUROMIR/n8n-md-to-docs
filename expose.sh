#!/bin/bash

# Универсальный скрипт для создания туннеля к md2doc-converter
# Пробует несколько сервисов туннелей по очереди

set -e

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

LOGS_DIR="logs"
mkdir -p "$LOGS_DIR"

TUNNEL_PID_FILE="$LOGS_DIR/tunnel.pid"
BACKEND_LOG="$LOGS_DIR/backend-tunnel.log"

# Функция очистки
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Остановка туннеля...${NC}"
    if [ -f "$TUNNEL_PID_FILE" ]; then
        TUNNEL_PID=$(cat "$TUNNEL_PID_FILE")
        if ps -p "$TUNNEL_PID" > /dev/null 2>&1; then
            kill "$TUNNEL_PID" 2>/dev/null || true
        fi
        rm -f "$TUNNEL_PID_FILE"
    fi
    pkill -f "ssh.*(localhost.run|serveo.net)" 2>/dev/null || true
    echo -e "${GREEN}✓ Очистка завершена${NC}"
}

trap cleanup EXIT INT TERM

echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        md2doc-converter Public Tunnel         ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo ""

# Проверка Docker
echo -e "${YELLOW}🔍 Проверка Docker контейнера...${NC}"
if ! docker ps | grep -q "md2doc-converter"; then
    echo -e "${YELLOW}  Запускаю контейнер...${NC}"
    docker compose up -d
    sleep 5
fi

# Проверка health
echo -e "${YELLOW}🏥 Проверка health endpoint...${NC}"
if ! curl -s http://localhost:8080/health | grep -q "ok"; then
    echo -e "${RED}✗ Сервер не отвечает${NC}"
    docker compose logs --tail 20 md2doc-converter
    exit 1
fi
echo -e "${GREEN}✓ Сервер работает${NC}"
echo ""

# Функция для попытки создания туннеля через localhost.run
try_localhost_run() {
    echo -e "${YELLOW}Пробую localhost.run...${NC}"
    > "$BACKEND_LOG"

    ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o ServerAliveInterval=60 \
        -R 80:localhost:8080 \
        nokey@localhost.run > "$BACKEND_LOG" 2>&1 &

    TUNNEL_PID=$!
    echo "$TUNNEL_PID" > "$TUNNEL_PID_FILE"

    # Ждём URL
    for i in {1..30}; do
        if [ -f "$BACKEND_LOG" ]; then
            # Ищем URL в формате .lhr.life (основной публичный URL localhost.run)
            # Это реальный публичный URL, не admin URL!
            TUNNEL_URL=$(grep -oE "[a-zA-Z0-9]+\.lhr\.life" "$BACKEND_LOG" | head -1)
            if [ -n "$TUNNEL_URL" ]; then
                TUNNEL_URL="https://${TUNNEL_URL}"
                echo -e "${GREEN}✓ Туннель создан: $TUNNEL_URL${NC}"
                return 0
            fi
        fi
        sleep 1
    done

    # Не получилось
    kill "$TUNNEL_PID" 2>/dev/null || true
    return 1
}

# Функция для попытки создания туннеля через serveo.net
try_serveo() {
    echo -e "${YELLOW}Пробую serveo.net...${NC}"
    > "$BACKEND_LOG"

    ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -o ServerAliveInterval=60 \
        -R 80:localhost:8080 \
        serveo.net > "$BACKEND_LOG" 2>&1 &

    TUNNEL_PID=$!
    echo "$TUNNEL_PID" > "$TUNNEL_PID_FILE"

    # Ждём URL
    for i in {1..20}; do
        if [ -f "$BACKEND_LOG" ]; then
            TUNNEL_URL=$(grep -oE "https?://[a-zA-Z0-9.-]+\.serveo\.net" "$BACKEND_LOG" | head -1)
            if [ -n "$TUNNEL_URL" ]; then
                echo -e "${GREEN}✓ Туннель создан: $TUNNEL_URL${NC}"
                return 0
            fi
        fi
        sleep 1
    done

    # Не получилось
    kill "$TUNNEL_PID" 2>/dev/null || true
    return 1
}

# Пробуем сервисы по очереди
echo -e "${YELLOW}🌐 Создание туннеля...${NC}"
echo ""

TUNNEL_URL=""

if try_localhost_run; then
    SERVICE="localhost.run"
elif try_serveo; then
    SERVICE="serveo.net"
else
    echo -e "${RED}✗ Не удалось создать туннель ни через один сервис${NC}"
    echo ""
    echo -e "${YELLOW}Попробуйте альтернативные варианты:${NC}"
    echo "1. ngrok: https://ngrok.com/"
    echo "2. cloudflared: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/"
    echo ""
    echo "Или разверните на сервере с nginx."
    exit 1
fi

# Успех!
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                   Туннель готов!              ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✓ Сервис: $SERVICE${NC}"
echo -e "${GREEN}✓ URL: $TUNNEL_URL${NC}"
echo ""
echo -e "${YELLOW}🧪 Тестовые команды:${NC}"
echo ""
echo -e "${BLUE}# Health check:${NC}"
echo "curl $TUNNEL_URL/health"
echo ""
echo -e "${BLUE}# Конвертация с формулами (нужен OAuth токен из n8n):${NC}"
cat << EOF
curl -X POST $TUNNEL_URL/ \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer YOUR_N8N_OAUTH_TOKEN" \\
  -d '{
    "output": "# Test Document\\n\\n## Formula\\n\\nInline: \$x^2 + y^2 = z^2\$\\n\\nDisplay: \$\$V = \\\\sum_{t=1}^{n} \\\\frac{ЧДП_t}{(1+r)^t}\$\$",
    "fileName": "Test Formulas"
  }'
EOF
echo ""
echo -e "${YELLOW}📊 Полезные команды:${NC}"
echo "  Логи туннеля:  tail -f $BACKEND_LOG"
echo "  Логи сервера:  docker compose logs -f md2doc-converter"
echo "  Остановить:    ./stop-tunnel.sh или Ctrl+C"
echo ""
echo -e "${GREEN}✓ Туннель активен${NC}"
echo -e "${YELLOW}⚠️  Нажмите Ctrl+C для остановки${NC}"
echo ""

# Держим туннель активным
while ps -p $(cat "$TUNNEL_PID_FILE") > /dev/null 2>&1; do
    sleep 5
done

echo -e "${RED}✗ Туннель закрылся${NC}"
