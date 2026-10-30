#!/usr/bin/env bash

# Включаем строгий режим: прерывать при ошибках, пустых переменных и ошибках в пайпах
set -euo pipefail

# Цветовая разметка для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

OPENSEARCH_ENV_FILE_NAME=".opensearch_env"

OPENSEARCH_USER="admin"

# Отыскиваем директорию, в которой лежит этот скрипт
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/$OPENSEARCH_ENV_FILE_NAME" ]; then
    # Включаем автоматический экспорт всех загружаемых переменных
    set -a
    source "$SCRIPT_DIR/$OPENSEARCH_ENV_FILE_NAME"
    set +a
fi

# Функция для вывода справки
usage() {
    echo -e "${YELLOW}Использование:${NC} $0 {sberlinux|ubuntu|x5}"
    echo "Пример: sudo $0 sberlinux"
    exit 1
}

# 0. Валидация аргументов и окружения
if [ "$#" -ne 1 ]; then
    echo -e "${RED}Ошибка: Неверное количество аргументов.${NC}"
    usage
fi

ENV_TYPE=$(echo "$1" | tr '[:upper:]' '[:lower:]')

if [[ "$ENV_TYPE" != "sberlinux" && "$ENV_TYPE" != "ubuntu" && "$ENV_TYPE" != "x5" ]]; then
    echo -e "${RED}Ошибка: Неверный аргумент '$1'. Допустимы только 'sberlinux' или 'ubuntu или x5'.${NC}"
    usage
fi

# Проверка прав root (требуется для очистки rsyslog)
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Ошибка: Этот скрипт должен выполняться от имени root (через sudo).${NC}"
    exit 1
fi

echo -e "${GREEN}>>> Начало очистки окружения для: ${ENV_TYPE}${NC}\n"


# ---------------------------------------------------------------------
# 1. Очистка rsyslog
# ---------------------------------------------------------------------
echo -e "${YELLOW}[1/3] Очистка rsyslog...${NC}"

# Переменная для управления именем сервиса в зависимости от ОС
# (В SberLinux/RHEL обычно rsyslog, в Ubuntu может быть rsyslog)
SERVICE_NAME="rsyslog"

if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo "Остановка сервиса $SERVICE_NAME..."
    systemctl stop "$SERVICE_NAME"
fi

# Очищаем (усекаем) файлы логов, не удаляя сами файлы (чтобы не ломать права)
if [ -f /var/log/rsyslog/all.log ]; then
    echo "Очистка /var/log/rsyslog/all.log..."
    echo "" > /var/log/rsyslog/all.log
fi

if [ -f /var/log/rsyslog/all-json.log ]; then
    echo "Очистка /var/log/rsyslog/all-json.log..."
    echo "" > /var/log/rsyslog/all-json.log
fi

echo "Запуск сервиса $SERVICE_NAME..."
systemctl start "$SERVICE_NAME"
echo -e "${GREEN}✔ Логи rsyslog успешно очищены.${NC}\n"


# ---------------------------------------------------------------------
# 2. Очистка OpenSearch
# ---------------------------------------------------------------------
echo -e "${YELLOW}[2/3] Очистка OpenSearch (удаление пользовательских индексов)...${NC}"

# Переменные для подключения к OpenSearch (измените под ваш контур или вынесите в env)
if [ -z "${opensearch_fqdn:-}" ] || [ -z "${opensearch_pass:-}" ]; then
    echo -e "${RED}Ошибка: Переменные окружения opensearch_fqdn и opensearch_pass должны быть заданы!${NC}"
    echo "Пример запуска: opensearch_fqdn='os.local' opensearch_pass='mypass' sudo -E ./script.sh sberlinux"
    exit 1
fi

# Пробуем отправить DELETE запрос.
# Используем флаг -s (silent) и -w для проверки HTTP-кода.
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -X DELETE "https://${opensearch_fqdn}:9200/*,-.*" -u "${OPENSEARCH_USER}:${opensearch_pass}" || echo "000")

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
    echo -e "${GREEN}✔ Индексы OpenSearch успешно удалены (HTTP $HTTP_CODE).${NC}\n"
elif [[ "$HTTP_CODE" == "400" ]]; then
    echo -e "${YELLOW}⚠ Предупреждение (HTTP 400): Возможно, включена защита 'action.destructive_requires_name'. Пользовательские индексы не удалены.${NC}\n"
else
    echo -e "${RED}❌ Не удалось очистить OpenSearch. HTTP код ответа: $HTTP_CODE${NC}\n"
    # Не прерываем скрипт полностью, если OpenSearch недоступен, переходим к NFS
fi


# ---------------------------------------------------------------------
# 3. Очистка NFS директории
# ---------------------------------------------------------------------
NFS_TARGET_DIR="/mnt/NFS_EXPORT/k0s/${ENV_TYPE}"

echo -e "${YELLOW}[3/3] Очистка NFS директории: ${NFS_TARGET_DIR}/* ...${NC}"

# Защита от удаления корня: проверяем, что папка существует и путь не пустой
if [ -d "$NFS_TARGET_DIR" ]; then
    # Проверяем, не пустая ли папка, чтобы избежать ошибок curl/rm
    if [ "$(ls -A "$NFS_TARGET_DIR")" ]; then
        # Удаляем только содержимое папки аргумента
        rm -rf "${NFS_TARGET_DIR:?}"/*
        echo -e "${GREEN}✔ Содержимое директории ${NFS_TARGET_DIR} успешно удалено.${NC}\n"
    else
        echo "Директория ${NFS_TARGET_DIR} уже пуста."
    fi
else
    echo -e "${RED}❌ Ошибка: Директория ${NFS_TARGET_DIR} не существует. Пропустите этот шаг или проверьте точку монтирования.${NC}\n"
fi

echo -e "${GREEN}>>> Очистка для окружения '${ENV_TYPE}' завершена!${NC}"
