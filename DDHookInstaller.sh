#!/bin/bash

# Стили и цвета
BOLD='\033[1m'
B_CYAN='\033[1;36m'
B_GREEN='\033[1;32m'
B_YELLOW='\033[1;33m'
B_RED='\033[1;31m'
NC='\033[0m'

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo -e "${B_RED}${BOLD}✖ ОШИБКА: Этот скрипт должен быть запущен от имени root!${NC}"
    exit 1
fi

clear

echo -e "${B_CYAN}${BOLD}=== Установщик DuckDNS Wildcard Hook ===${NC}\n"

# 1. Запрос данных
echo -e "${B_YELLOW}${BOLD}Введите ваш домен (например, myhome.duckdns.org):${NC}"
read FULL_DOMAIN

echo -e "${B_YELLOW}${BOLD}Введите ваш DuckDNS Token:${NC}"
read DUCK_TOKEN

# 2. Очистка старых данных
echo -e "\n${B_CYAN}${BOLD}Удаление устаревшей конфигурации...${NC}"
RENEWAL_FILE="/etc/letsencrypt/renewal/$FULL_DOMAIN.conf"
if [ -f "$RENEWAL_FILE" ]; then
    sed -i '/manual_auth_hook/d; /manual_cleanup_hook/d; s/authenticator = manual/authenticator = dns-duckdns/g' "$RENEWAL_FILE"
    echo -e "${B_GREEN}${BOLD}✔ Старая конфигурация успешно очищена.${NC}"
else
    echo -e "${B_CYAN}${BOLD}✔ Предыдущая конфигурация не обнаружена.${NC}"
fi

# 3. Проверка и установка плагина
echo -e "\n${B_CYAN}${BOLD}Проверка наличия плагина в системе...${NC}"
if ! certbot plugins | grep -q "dns-duckdns"; then
    echo -e "${B_YELLOW}${BOLD}Установка необходимых компонентов...${NC}"
    apt-get update -qq && apt-get install -y -qq python3-pip > /dev/null
    pip3 install -q certbot-dns-duckdns
    echo -e "${B_GREEN}${BOLD}✔ Плагин успешно установлен.${NC}"
else
    echo -e "${B_GREEN}${BOLD}✔ Плагин уже установлен.${NC}"
fi

# 4. Создание файла учетных данных
echo -e "\n${B_CYAN}${BOLD}Сохранение данных для авторизации...${NC}"
CRED_FILE="/etc/letsencrypt/duckdns.ini"
echo "dns_duckdns_token = $DUCK_TOKEN" > "$CRED_FILE"
chmod 600 "$CRED_FILE"
echo -e "${B_GREEN}${BOLD}✔ Новый файл авторизации создан: $CRED_FILE${NC}"

# 5. Выполнение Certbot
echo -e "\n${B_CYAN}${BOLD}Запуск процесса выпуска сертификата...${NC}"
echo -e "${B_YELLOW}${BOLD}Ожидание обновления DNS записей (120 секунд)...${NC}"

certbot certonly --authenticator dns-duckdns \
  --dns-duckdns-credentials "$CRED_FILE" \
  --dns-duckdns-propagation-seconds 120 \
  --agree-tos \
  --register-unsafely-without-email \
  --force-renewal \
  -d "$FULL_DOMAIN" -d "*.$FULL_DOMAIN"

# 6. Проверка статуса
if [ $? -eq 0 ]; then
    echo -e "\n${B_GREEN}${BOLD}✔ СЕРТИФИКАТЫ УСПЕШНО ПОЛУЧЕНЫ!${NC}"
    echo -e "${B_GREEN}${BOLD}Текущая конфигурация сохранена. Продление будет происходить автоматически.${NC}"
    echo -e "${B_CYAN}${BOLD}Путь к файлам: /etc/letsencrypt/live/$FULL_DOMAIN/${NC}"
else
    echo -e "\n${B_RED}${BOLD}✖ ОШИБКА ПРИ ВЫПУСКЕ!${NC}"
    echo -e "${B_RED}${BOLD}Проверьте корректность данных и доступ к сети.${NC}"
fi

echo -e "\n${B_CYAN}${BOLD}=============================================${NC}"
