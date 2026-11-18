#!/bin/sh
# Установка WOL Gateway в системные каталоги OpenWrt.

set -eu

# Определяем каталог репозитория независимо от текущего рабочего каталога.
SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" != "0" ]; then
    echo "Запустите установку от root: sh install.sh" >&2
    exit 1
fi

# Создаём каталоги приложения.
mkdir -p /usr/bin /usr/lib/wol-gateway /etc/init.d

# Устанавливаем исполняемый файл и внутренние модули.
cp "$SCRIPT_DIR/files/usr/bin/wol-gateway" /usr/bin/wol-gateway
cp "$SCRIPT_DIR/files/usr/lib/wol-gateway/config.sh" /usr/lib/wol-gateway/config.sh
cp "$SCRIPT_DIR/files/usr/lib/wol-gateway/telegram.sh" /usr/lib/wol-gateway/telegram.sh
cp "$SCRIPT_DIR/files/usr/lib/wol-gateway/actions.sh" /usr/lib/wol-gateway/actions.sh
cp "$SCRIPT_DIR/files/etc/init.d/wol-gateway" /etc/init.d/wol-gateway

chmod 0755 /usr/bin/wol-gateway /etc/init.d/wol-gateway
chmod 0644 /usr/lib/wol-gateway/*.sh

# Не перезаписываем уже существующий пример или рабочую конфигурацию.
if [ ! -e /etc/wol-gateway.env.example ]; then
    cp "$SCRIPT_DIR/files/etc/wol-gateway.env.example" /etc/wol-gateway.env.example
    chmod 0600 /etc/wol-gateway.env.example
fi

echo "WOL Gateway установлен."
echo "Создайте /etc/wol-gateway.env из /etc/wol-gateway.env.example,"
echo "заполните токен и устройства, затем выполните:"
echo "  chown root:root /etc/wol-gateway.env"
echo "  chmod 600 /etc/wol-gateway.env"
echo "  /etc/init.d/wol-gateway enable"
echo "  /etc/init.d/wol-gateway start"
