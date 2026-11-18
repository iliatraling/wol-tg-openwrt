# Установка WOL Telegram Gateway на OpenWrt

Инструкция проверена на Netis NX32U с OpenWrt 25.12.6.

## 1. Проверяем роутер и зависимости

Подключитесь к роутеру по SSH и выполните диагностические команды:

```sh
echo "===== OPENWRT ====="
ubus call system board

echo "===== NETWORK INTERFACES ====="
ip link show
ip addr show

echo "===== INSTALLED PACKAGES ====="
opkg list-installed 2>/dev/null | grep -E '^(curl|etherwake|libubox|ca-bundle)' || true
apk list --installed 2>/dev/null | grep -E 'curl|etherwake|libubox|ca-bundle' || true

echo "===== COMMANDS ====="
command -v curl
command -v etherwake
command -v ping

echo "===== JSHN ====="
ls -l /usr/share/libubox/jshn.sh

echo "===== ETHERWAKE HELP ====="
etherwake --help 2>&1
```

Примечания:

- В OpenWrt 25.12 используется `apk`. В более старых версиях может использоваться `opkg`.
- В некоторых сборках BusyBox команда `ip -br` не поддерживается. Поэтому здесь используются `ip link show` и `ip addr show`.
- Для работы шлюза нужны `curl`, TLS-сертификаты, `etherwake` и библиотека `jshn.sh`.
- Если какая-либо зависимость отсутствует, установите пакеты. Для OpenWrt 25.12:

```sh
apk update
apk add curl ca-bundle etherwake libubox
```

Проверить наличие пакета `etherwake` в репозиториях можно командой:

```sh
apk search etherwake
```

## 2. Определяем LAN-интерфейс

Для параметра `NETWORK_INTERFACE` нужен интерфейс локальной сети, через который роутер отправит Wake-on-LAN пакет.

Выполните:

```sh
echo "===== LAN CONFIG ====="
uci show network.lan

echo "===== LAN STATUS ====="
ubus call network.interface.lan status

echo "===== NETWORK DEVICES ====="
ip link show

echo "===== IP ADDRESSES ====="
ip addr show
```

В выводе `ubus` найдите поле `l3_device` или `device`, а в выводе `ip addr` — интерфейс с LAN-адресом роутера.

Обычно это `br-lan`. Именно его укажите в `NETWORK_INTERFACE`. Не копируйте значение автоматически: сверьте его с фактической конфигурацией роутера.

## 3. Копируем файлы на роутер

На компьютере с Windows откройте PowerShell. Скачайте ZIP-архив репозитория с GitHub и распакуйте его. Затем передайте каталог на роутер:

```powershell
scp -O -r C:\NX32U-OpenWrt\wol-gateway-src\wol-tg-openwrt-main root@192.168.0.1:/tmp/
```

Замените путь к каталогу и IP-адрес роутера, если у вас они отличаются.

Ключ `-O` включает старый протокол SCP. Он нужен для сборок OpenWrt, в которых не установлен SFTP-сервер.

## 4. Устанавливаем приложение

Вернитесь в SSH-сессию роутера:

```sh
cd /tmp/wol-tg-openwrt-main
sh install.sh
```

Установщик разместит файлы программы в системных каталогах OpenWrt.

## 5. Создаём конфигурацию

Создайте рабочий конфигурационный файл из шаблона:

```sh
cp /etc/wol-gateway.env.example /etc/wol-gateway.env
chown root:root /etc/wol-gateway.env
chmod 600 /etc/wol-gateway.env
vi /etc/wol-gateway.env
```

Укажите параметры своего Telegram-бота и устройств. Пример для одного домашнего ПК:

```ini
BOT_TOKEN="ТОКЕН_ТВОЕГО_БОТА"
ALLOWED_USER_IDS="422503387"

TARGET_NAMES="home"
TARGET_LABELS="Домашний ПК"
TARGET_MACS="18:C0:4D:6E:81:5D"
TARGET_IPS="192.168.0.134"

DEFAULT_TARGETS="home"
NETWORK_INTERFACE="br-lan"
```

Замените значения на свои:

- `BOT_TOKEN` — токен, полученный у [@BotFather](https://t.me/BotFather). Не отправляйте его в чаты и не добавляйте в Git.
- `ALLOWED_USER_IDS` — ваш Telegram User ID. Только указанные ID смогут управлять ботом.
- `TARGET_MACS` — MAC-адрес устройства, которое нужно включать.
- `TARGET_IPS` — IP-адрес устройства, используемый командой `/status`.
- `NETWORK_INTERFACE` — LAN-интерфейс, определённый на шаге 2.

`TARGET_NAMES`, `TARGET_LABELS`, `TARGET_MACS` и `TARGET_IPS` должны содержать одинаковое количество элементов в одинаковом порядке.

Токен хранится только в `/etc/wol-gateway.env`. Не публикуйте содержимое этого файла и не присылайте его в переписке.

## 6. Запускаем службу

Выполните на роутере:

```sh
/etc/init.d/wol-gateway enable
/etc/init.d/wol-gateway start
```

Команда `enable` добавляет службу в автозапуск, а `start` запускает её сейчас.

## 7. Проверяем работу

Проверьте состояние службы и журнал:

```sh
/etc/init.d/wol-gateway status
logread -e wol-gateway
```

Откройте чат со своим Telegram-ботом и отправьте:

- `/help` — список команд;
- `/wake` — отправить WOL-пакет устройству из `DEFAULT_TARGETS`;
- `/status` — проверить доступность устройства по IP.

Успешная отправка WOL-пакета не гарантирует включение компьютера. Для работы Wake-on-LAN также должны быть включены соответствующие настройки BIOS/UEFI и сетевого адаптера.

## Важные замечания

- Одновременно должен работать только один клиент, получающий обновления Telegram для этого токена. Остановите другие экземпляры бота перед запуском службы на OpenWrt.
- Входящие порты на WAN для работы бота не нужны: роутер сам устанавливает исходящее HTTPS-соединение с Telegram.
- При повторной установке не удаляйте `/etc/wol-gateway.env`: в нём хранится ваш токен и настройки устройств.
