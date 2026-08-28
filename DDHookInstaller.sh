#!/bin/bash

# Стили и цвета
BOLD='\033[1m'
B_CYAN='\033[1;36m'
B_GREEN='\033[1;32m'
B_YELLOW='\033[1;33m'
B_RED='\033[1;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${B_RED}Ошибка: Запустите от имени root.${NC}"
    exit 1
fi

echo -e "${B_CYAN}Конфигурация DuckDNS Wildcard Hook${NC}"

# 1. Запрос данных
read -p "Введите ваш домен (например, domain.duckdns.org): " FULL_DOMAIN
read -p "Введите ваш DuckDNS Token: " DUCK_TOKEN

# 2. Очистка старых данных
RENEWAL_FILE="/etc/letsencrypt/renewal/$FULL_DOMAIN.conf"
if [ -f "$RENEWAL_FILE" ]; then
    echo -e "${B_YELLOW}Очистка старой конфигурации...${NC}"
    sed -i '/manual_auth_hook/d; /manual_cleanup_hook/d; s/authenticator = manual/authenticator = dns-duckdns/g' "$RENEWAL_FILE"
fi

# 3. Проверка и установка компонентов
if ! certbot plugins | grep -q "dns-duckdns"; then
    echo -e "${B_YELLOW}Установка необходимых компонентов...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y certbot cron python3-pip -qq
    pip3 install -q certbot-dns-duckdns
fi

# 4. Создание файла учетных данных
CRED_FILE="/etc/letsencrypt/duckdns.ini"
echo "dns_duckdns_token = $DUCK_TOKEN" > "$CRED_FILE"
chmod 600 "$CRED_FILE"

# 5. Выполнение Certbot (с 3 попытками)
echo -e "${B_CYAN}Запуск процесса выпуска сертификата...${NC}"

SUCCESS=false
for i in {1..3}; do
    echo -e "${B_YELLOW}Попытка $i из 3...${NC}"
    certbot certonly --authenticator dns-duckdns \
      --dns-duckdns-credentials "$CRED_FILE" \
      --dns-duckdns-propagation-seconds 120 \
      --agree-tos \
      --register-unsafely-without-email \
      --force-renewal \
      -d "$FULL_DOMAIN" -d "*.$FULL_DOMAIN"

    if [ $? -eq 0 ]; then
        SUCCESS=true
        break
    fi

    if [ $i -lt 3 ]; then
        echo -e "${B_RED}Ошибка при выпуске. Повтор через 10 секунд...${NC}"
        sleep 10
    fi
done

# 6. Проверка статуса
if [ "$SUCCESS" = true ]; then
    echo -e "${B_GREEN}Сертификаты для $FULL_DOMAIN успешно получены!${NC}"
    
    read -p "Создать задачу в crontab для автоматического продления? [y/N]: " CRON_CHOICE
    if [[ "$CRON_CHOICE" =~ ^[Yy]$ ]]; then
        C_JOB="0 0,12 * * * certbot renew --quiet"
        (crontab -l 2>/dev/null | grep -v "certbot renew" ; echo "$C_JOB") | crontab -
        echo -e "${B_YELLOW}Задача в crontab создана.${NC}"
    fi
else
    echo -e "${B_RED}Ошибка: Не удалось выпустить сертификат после 3 попыток.${NC}"
    exit 1
fi

echo -e "${B_GREEN}DuckDNS Wildcard Hook успешно настроен!${NC}"
