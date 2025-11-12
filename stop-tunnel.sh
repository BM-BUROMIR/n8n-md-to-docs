#!/bin/bash

# Скрипт для остановки туннеля serveo.net

set -e

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

LOGS_DIR="logs"
TUNNEL_PID_FILE="$LOGS_DIR/tunnel.pid"

echo -e "${YELLOW}🛑 Остановка туннеля md2doc-converter...${NC}"
echo ""

# Остановка по PID файлу
if [ -f "$TUNNEL_PID_FILE" ]; then
    TUNNEL_PID=$(cat "$TUNNEL_PID_FILE")
    if ps -p "$TUNNEL_PID" > /dev/null 2>&1; then
        echo -e "${YELLOW}Останавливаю туннель (PID: $TUNNEL_PID)...${NC}"
        kill "$TUNNEL_PID" 2>/dev/null || true
        sleep 2
        if ! ps -p "$TUNNEL_PID" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Туннель остановлен${NC}"
        else
            echo -e "${YELLOW}⚠️  Принудительная остановка...${NC}"
            kill -9 "$TUNNEL_PID" 2>/dev/null || true
            echo -e "${GREEN}✓ Туннель принудительно остановлен${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Процесс с PID $TUNNEL_PID не найден${NC}"
    fi
    rm -f "$TUNNEL_PID_FILE"
else
    echo -e "${YELLOW}⚠️  PID файл не найден${NC}"
fi

# Убиваем все SSH процессы к serveo.net (на всякий случай)
echo -e "${YELLOW}Проверка остаточных SSH процессов...${NC}"
if pkill -f "ssh.*serveo.net" 2>/dev/null; then
    echo -e "${GREEN}✓ Остаточные SSH процессы остановлены${NC}"
else
    echo -e "${GREEN}✓ Остаточных процессов не найдено${NC}"
fi

echo ""
echo -e "${GREEN}✓ Очистка завершена${NC}"
echo ""
echo -e "${YELLOW}Контейнер md2doc-converter всё ещё работает.${NC}"
echo -e "Для остановки контейнера выполните: ${GREEN}docker compose down${NC}"
