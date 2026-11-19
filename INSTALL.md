# Установка WOL Telegram Gateway на OpenWrt

## 1. Зависимости

Для OpenWrt 25.12:
```sh
apk update
apk add curl ca-bundle etherwake libubox
```

Проверьте LAN-интерфейс:
```sh
ubus call network.interface.lan status
ip link show
```
Обычно используется `br-lan`, но укажите фактический интерфейс.

## 2. Сборка и установка

Соберите оба пакета через OpenWrt SDK/buildroot для версии и архитектуры роутера. Установка:
```sh
apk add ./wol-gateway_*.apk
apk add ./luci-app-wol-gateway_*.apk
```
Для OpenWrt до 25.12 используйте подходящий SDK и `opkg`.

## 3. Конфигурация

Создайте рабочий ENV:
```sh
cp /etc/wol-gateway.env.example /etc/wol-gateway.env
chown root:root /etc/wol-gateway.env
chmod 600 /etc/wol-gateway.env
vi /etc/wol-gateway.env
```

Заполните токен, разрешённые Telegram ID, алиасы, названия, MAC, IP, DEFAULT_TARGETS и NETWORK_INTERFACE. Те же поля доступны в **Services → WOL Gateway**. Токен в интерфейсе не показывается; пустое поле не изменяет сохранённый токен.

Списки TARGET_NAMES, TARGET_LABELS, TARGET_MACS и TARGET_IPS должны содержать одинаковое количество элементов в одинаковом порядке. Разделитель — запятая. Если IP не требуется, укажите `0`.

## 4. Запуск

```sh
/etc/init.d/wol-gateway enable
/etc/init.d/wol-gateway start
```

LuCI находится в меню **Services → WOL Gateway**.

## 5. Логи

Логирование использует штатный кольцевой буфер OpenWrt `logd` в RAM. Постоянный файл на flash не создаётся. Буфер общий для системы, его размер задаётся системной конфигурацией; старые записи вытесняются при заполнении. После перезагрузки журнал очищается.

```sh
logread -e wol-gateway
wol-gateway log status
wol-gateway log off
wol-gateway log on
```

При выключенном подробном логировании INFO-сообщения подавляются, ошибки продолжают записываться.

## 6. Обновление и удаление

Обновляйте пакеты сборками для своей версии OpenWrt:
```sh
apk add --allow-downgrades ./wol-gateway_НОВАЯ_ВЕРСИЯ.apk
apk add --allow-downgrades ./luci-app-wol-gateway_НОВАЯ_ВЕРСИЯ.apk
```
Не удаляйте `/etc/wol-gateway.env`: там хранятся токен и настройки устройств.

Удалить только интерфейс:
```sh
apk del luci-app-wol-gateway
```
Основная служба останется установленной и продолжит работать.

Удалить основную службу:
```sh
/etc/init.d/wol-gateway stop
/etc/init.d/wol-gateway disable
apk del wol-gateway
```
Рабочий ENV удаляется отдельно и только при необходимости.
