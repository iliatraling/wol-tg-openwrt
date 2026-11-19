# WOL Telegram Gateway for OpenWrt

Приложение для удалённого включения компьютеров и других устройств по Wake-on-LAN через Telegram-бота.

## Два независимых пакета

- **wol-gateway** — служба Telegram, WOL, конфигурация и логирование.
- **luci-app-wol-gateway** — LuCI-интерфейс, RPC, управление службой, ENV и просмотр журнала.

Удаление LuCI-пакета не удаляет и не останавливает основную службу. Пакет интерфейса не зависит от основного пакета, но для управления сервисом он должен быть установлен.

## LuCI

В меню **Services → WOL Gateway** доступны:

- состояние службы и автозапуска;
- запуск, остановка и перезапуск;
- включение и отключение автозапуска;
- все переменные текущего ENV: `BOT_TOKEN`, `ALLOWED_USER_IDS`, `TARGET_NAMES`, `TARGET_LABELS`, `TARGET_MACS`, `TARGET_IPS`, `DEFAULT_TARGETS`, `NETWORK_INTERFACE`;
- проверка конфигурации перед сохранением;
- проверка Telegram Bot API;
- просмотр последних 30 сообщений;
- включение и выключение подробного логирования.

Токен скрыт. Он не возвращается из RPC и не отображается в поле. Чтобы заменить токен, введите новый; пустое поле сохраняет текущий.

CSV-списки вводятся через запятую. Порядок и количество элементов в TARGET_NAMES, TARGET_LABELS, TARGET_MACS и TARGET_IPS должны совпадать. Если IP не нужен, укажите `0`.

## Логи и флеш-память

WOL Gateway использует системный журнал OpenWrt: сообщения отправляются через `logger`, просмотр выполняется командой `logread`. Журнал хранится в кольцевом буфере `logd` в RAM. Отдельный файл `/tmp/wol-gateway.log` больше не создаётся. Буфер общий для системы, ограничивается настройкой OpenWrt и перезаписывает старые сообщения при заполнении. После перезагрузки содержимое теряется.

Переключатель подробного логирования подавляет обычные INFO-сообщения. Критические ошибки остаются в журнале.

SSH:
```sh
wol-gateway log status
wol-gateway log off
wol-gateway log on
logread -e wol-gateway
```

## Сборка пакетов

Пакеты собираются через OpenWrt SDK/buildroot для конкретной версии и архитектуры. Скопируйте каталоги `packages/wol-gateway` и `packages/luci-app-wol-gateway` в свой feed либо в каталог `package/` дерева OpenWrt. Выберите пакеты в `make menuconfig` и соберите:

```sh
make package/wol-gateway/compile V=s
make package/luci-app-wol-gateway/compile V=s
```

На OpenWrt 25.12 устанавливайте APK:
```sh
apk add ./wol-gateway_*.apk
apk add ./luci-app-wol-gateway_*.apk
```

Для более ранних выпусков используйте соответствующий SDK и `opkg`.

## Документация

- [Установка и настройка](INSTALL.md)
- [Документация LuCI-пакета](packages/luci-app-wol-gateway/README.md)

Основные команды Telegram: `/help`, `/wake`, `/status`. Успешная отправка Magic Packet не гарантирует включение устройства.
