#!/bin/bash

# Скрипт для запуска md2doc-converter и создания туннеля через serveo.net
# Использование: ./start-tunnel.sh [alias]
# Пример: ./start-tunnel.sh md2doc

set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Директория логов
LOGS_DIR="logs"
mkdir -p "$LOGS_DIR"

# PID файлы
TUNNEL_PID_FILE="$LOGS_DIR/tunnel.pid"
BACKEND_LOG="$LOGS_DIR/backend-tunnel.log"

# Функция очистки при выходе
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Остановка туннеля...${NC}"
    if [ -f "$TUNNEL_PID_FILE" ]; then
        TUNNEL_PID=$(cat "$TUNNEL_PID_FILE")
        if ps -p "$TUNNEL_PID" > /dev/null 2>&1; then
            kill "$TUNNEL_PID" 2>/dev/null || true
            echo -e "${GREEN}✓ Туннель остановлен (PID: $TUNNEL_PID)${NC}"
        fi
        rm -f "$TUNNEL_PID_FILE"
    fi

    # Также убиваем все SSH процессы к serveo.net
    pkill -f "ssh.*serveo.net" 2>/dev/null || true

    echo -e "${GREEN}✓ Очистка завершена${NC}"
}

# Установка обработчика сигналов
trap cleanup EXIT INT TERM

echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   md2doc-converter Tunnel Setup (serveo.net)  ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo ""

# Проверка, что Docker контейнер запущен
echo -e "${YELLOW}🔍 Проверка Docker контейнера...${NC}"
if ! docker ps | grep -q "md2doc-converter"; then
    echo -e "${RED}✗ Контейнер md2doc-converter не запущен${NC}"
    echo -e "${YELLOW}  Запускаю контейнер...${NC}"
    docker compose up -d
    echo -e "${YELLOW}  Ожидание запуска (5 секунд)...${NC}"
    sleep 5
fi

# Проверка health endpoint
echo -e "${YELLOW}🏥 Проверка health endpoint...${NC}"
if curl -s http://localhost:8080/health | grep -q "ok"; then
    echo -e "${GREEN}✓ Сервер работает${NC}"
else
    echo -e "${RED}✗ Сервер не отвечает на localhost:8080${NC}"
    echo -e "${YELLOW}  Логи контейнера:${NC}"
    docker compose logs --tail 20 md2doc-converter
    exit 1
fi
echo ""

# Получение alias из аргумента или использование дефолтного
ALIAS="${1:-md2doc}"
echo -e "${YELLOW}🌐 Настройка туннеля...${NC}"
echo -e "   Alias: ${GREEN}$ALIAS${NC}"
echo -e "   Local: ${GREEN}localhost:8080${NC}"
echo ""

# Очистка старых логов
> "$BACKEND_LOG"

# Создание туннеля
echo -e "${YELLOW}1️⃣ Создание туннеля (localhost:8080 → serveo.net)...${NC}"
ssh -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    -R "${ALIAS}:80:localhost:8080" \
    serveo.net > "$BACKEND_LOG" 2>&1 &

TUNNEL_PID=$!
echo "$TUNNEL_PID" > "$TUNNEL_PID_FILE"

echo -e "${GREEN}✓ Туннель запущен (PID: $TUNNEL_PID)${NC}"
echo -e "${YELLOW}   Ожидание установки соединения (10 секунд)...${NC}"
sleep 10

# Извлечение URL из логов
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Информация о туннеле             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo ""

if [ -f "$BACKEND_LOG" ]; then
    # Показываем последние строки лога с URL
    echo -e "${YELLOW}Лог туннеля:${NC}"
    tail -20 "$BACKEND_LOG"
    echo ""

    # Пытаемся извлечь URL
    TUNNEL_URL=$(grep -oE "https://[a-zA-Z0-9.-]+\.serveo\.net" "$BACKEND_LOG" | head -1)

    if [ -n "$TUNNEL_URL" ]; then
        echo -e "${GREEN}✓ Туннель успешно создан!${NC}"
        echo ""
        echo -e "${BLUE}📡 URL сервиса:${NC}"
        echo -e "   ${GREEN}${TUNNEL_URL}${NC}"
        echo ""
        echo -e "${YELLOW}🧪 Тестовые команды:${NC}"
        echo ""
        echo -e "${BLUE}# Health check:${NC}"
        echo "curl ${TUNNEL_URL}/health"
        echo ""
        echo -e "${BLUE}# Тест с OAuth токеном из n8n:${NC}"
        cat << EOF
curl -X POST ${TUNNEL_URL}/ \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer YOUR_N8N_OAUTH_TOKEN" \\
  -d '{
    "output": "# Test\\n\\n\$\$V = \\\\sum_{t=1}^{n} \\\\frac{ЧДП_t}{(1+r)^t}\$\$",
    "fileName": "Formula Test"
  }'
EOF
        echo ""
        echo -e "${YELLOW}📊 Мониторинг:${NC}"
        echo "  Логи туннеля:    tail -f $BACKEND_LOG"
        echo "  Логи сервера:    docker compose logs -f md2doc-converter"
        echo "  Статус туннеля:  ps -p $TUNNEL_PID"
        echo ""
        echo -e "${GREEN}✓ Сервис доступен извне через туннель${NC}"
        echo ""
        echo -e "${YELLOW}⚠️  Для остановки туннеля нажмите Ctrl+C${NC}"
        echo -e "${YELLOW}    Туннель будет автоматически закрыт при выходе${NC}"
        echo ""

        # Держим скрипт активным и показываем логи
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${BLUE}  Логи туннеля (Ctrl+C для остановки)${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo ""
        tail -f "$BACKEND_LOG"
    else
        echo -e "${RED}✗ Не удалось получить URL туннеля${NC}"
        echo -e "${YELLOW}  Проверьте лог: $BACKEND_LOG${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ Файл лога не найден: $BACKEND_LOG${NC}"
    exit 1
fi
