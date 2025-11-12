#!/bin/bash

# Скрипт для запуска md2doc-converter и создания туннеля через localhost.run
# Использование: ./start-tunnel-localtunnel.sh [subdomain]
# Пример: ./start-tunnel-localtunnel.sh md2doc

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

    # Также убиваем все SSH процессы к localhost.run
    pkill -f "ssh.*localhost.run" 2>/dev/null || true

    echo -e "${GREEN}✓ Очистка завершена${NC}"
}

# Установка обработчика сигналов
trap cleanup EXIT INT TERM

echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  md2doc-converter Tunnel Setup (localhost.run)║${NC}"
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

# Получение subdomain из аргумента (опционально)
SUBDOMAIN="${1:-}"
echo -e "${YELLOW}🌐 Настройка туннеля...${NC}"
if [ -n "$SUBDOMAIN" ]; then
    echo -e "   Subdomain: ${GREEN}$SUBDOMAIN${NC} (если доступен)"
fi
echo -e "   Local: ${GREEN}localhost:8080${NC}"
echo ""

# Очистка старых логов
> "$BACKEND_LOG"

# Создание туннеля
echo -e "${YELLOW}1️⃣ Создание туннеля (localhost:8080 → localhost.run)...${NC}"

if [ -n "$SUBDOMAIN" ]; then
    # С субдоменом
    ssh -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=60 \
        -o ServerAliveCountMax=3 \
        -R "${SUBDOMAIN}:80:localhost:8080" \
        nokey@localhost.run > "$BACKEND_LOG" 2>&1 &
else
    # Без субдомена (случайный URL)
    ssh -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=60 \
        -o ServerAliveCountMax=3 \
        -R 80:localhost:8080 \
        nokey@localhost.run > "$BACKEND_LOG" 2>&1 &
fi

TUNNEL_PID=$!
echo "$TUNNEL_PID" > "$TUNNEL_PID_FILE"

echo -e "${GREEN}✓ Туннель запущен (PID: $TUNNEL_PID)${NC}"
echo -e "${YELLOW}   Ожидание установки соединения (15 секунд)...${NC}"
sleep 15

# Извлечение URL из логов
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Информация о туннеле             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════╝${NC}"
echo ""

if [ -f "$BACKEND_LOG" ]; then
    # Показываем лог туннеля
    echo -e "${YELLOW}Лог туннеля:${NC}"
    cat "$BACKEND_LOG"
    echo ""

    # Пытаемся извлечь URL из разных форматов
    TUNNEL_URL=$(grep -oE "https?://[a-zA-Z0-9.-]+\.localhost\.run" "$BACKEND_LOG" | head -1)

    # Если не нашли, попробуем другой формат
    if [ -z "$TUNNEL_URL" ]; then
        TUNNEL_URL=$(grep -oE "https?://[a-zA-Z0-9.-]+\.lhr\.life" "$BACKEND_LOG" | head -1)
    fi

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
        echo ""

        # Держим скрипт активным и показываем логи
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo -e "${BLUE}  Туннель активен (Ctrl+C для остановки)${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        echo ""

        # Проверяем статус туннеля каждые 5 секунд
        while ps -p $TUNNEL_PID > /dev/null 2>&1; do
            sleep 5
        done

        echo -e "${RED}✗ Туннель неожиданно закрылся${NC}"
        tail -20 "$BACKEND_LOG"
    else
        echo -e "${YELLOW}⚠️  URL не найден в логе, но процесс работает${NC}"
        echo -e "${YELLOW}  Проверьте лог вручную: $BACKEND_LOG${NC}"
        echo -e "${YELLOW}  Туннель может всё ещё устанавливаться...${NC}"
        echo ""
        echo -e "${YELLOW}  Ожидание дополнительно 10 секунд...${NC}"
        sleep 10

        # Повторная попытка найти URL
        TUNNEL_URL=$(grep -oE "https?://[a-zA-Z0-9.-]+\.(localhost\.run|lhr\.life)" "$BACKEND_LOG" | head -1)
        if [ -n "$TUNNEL_URL" ]; then
            echo -e "${GREEN}✓ URL найден: ${TUNNEL_URL}${NC}"
        else
            echo -e "${RED}✗ URL всё ещё не найден${NC}"
            echo -e "${YELLOW}Полный лог:${NC}"
            cat "$BACKEND_LOG"
        fi
    fi
else
    echo -e "${RED}✗ Файл лога не найден: $BACKEND_LOG${NC}"
    exit 1
fi
