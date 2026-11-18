#!/bin/sh
# Загрузка и проверка конфигурации WOL Gateway.

WOL_CONFIG="${WOL_CONFIG:-/etc/wol-gateway.env}"
WOL_LOG_FILE="/tmp/wol-gateway.log"

wg_log() {
    # В журнал попадают только внутренние сообщения, без токена и текста пользователя.
    local message="$1"
    local timestamp
    local tmp_file

    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    umask 077
    printf '%s %s\n' "$timestamp" "$message" >> "$WOL_LOG_FILE"

    # Оставляем в RAM только последние 30 строк.
    if [ "$(wc -l < "$WOL_LOG_FILE" 2>/dev/null)" -gt 30 ]; then
        tmp_file="${WOL_LOG_FILE}.tmp"
        tail -n 30 "$WOL_LOG_FILE" > "$tmp_file" && mv "$tmp_file" "$WOL_LOG_FILE"
    fi

    logger -t wol-gateway "$message" 2>/dev/null
}

wg_error() {
    wg_log "ERROR: $1"
}

wg_csv_count() {
    # Подсчитывает элементы CSV-списка, не выполняя его содержимое.
    printf '%s\n' "$1" | awk -F ',' '{ print NF }'
}

wg_csv_get() {
    # Возвращает элемент списка по индексу, начиная с единицы.
    printf '%s\n' "$1" | awk -F ',' -v index="$2" '{
        value = $index
        gsub(/^[ \t]+|[ \t]+$/, "", value)
        sub(/\r$/, "", value)
        print value
    }'
}

wg_is_valid_ipv4() {
    # Проверяет IPv4 без обращения к DNS.
    printf '%s\n' "$1" | awk -F '.' '
        BEGIN { valid = 1 }
        NF != 4 { valid = 0 }
        NF == 4 {
            for (i = 1; i <= 4; i++) {
                if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) valid = 0
            }
        }
        END { exit !valid }
    '
}

wg_find_target() {
    # Поиск устройства по алиасу. Результат сохраняется в TARGET_*.
    local index
    local count
    local alias

    count="$(wg_csv_count "$TARGET_NAMES")"
    index=1

    while [ "$index" -le "$count" ]; do
        alias="$(wg_csv_get "$TARGET_NAMES" "$index")"
        if [ "$alias" = "$1" ]; then
            TARGET_INDEX="$index"
            TARGET_ALIAS="$alias"
            TARGET_LABEL="$(wg_csv_get "$TARGET_LABELS" "$index")"
            TARGET_MAC="$(wg_csv_get "$TARGET_MACS" "$index")"
            TARGET_IP="$(wg_csv_get "$TARGET_IPS" "$index")"
            return 0
        fi
        index=$((index + 1))
    done

    return 1
}

wg_validate_target_list() {
    # Проверяет, что каждый алиас существует и не повторяется в запросе.
    local list="$1"
    local item
    local rest
    local seen=" "

    case "$list" in
        ""|,*|*,|*,,*) return 1 ;;
    esac

    rest="$list"
    while :; do
        case "$rest" in
            *,*)
                item="${rest%%,*}"
                rest="${rest#*,}"
                ;;
            *)
                item="$rest"
                rest=""
                ;;
        esac

        case "$item" in
            ""|*[!a-z0-9-]*) return 1 ;;
        esac

        case "$seen" in
            *" $item "*) return 1 ;;
        esac
        seen="${seen}${item} "

        wg_find_target "$item" || return 1

        [ -n "$rest" ] || break
    done

    return 0
}

wg_load_config() {
    local owner
    local permissions
    local permission_value
    local names_count
    local labels_count
    local macs_count
    local ips_count
    local index
    local alias
    local label
    local mac
    local ip
    local id
    local seen

    if [ ! -f "$WOL_CONFIG" ] || [ -L "$WOL_CONFIG" ]; then
        wg_error "Конфигурационный файл отсутствует или является ссылкой"
        return 1
    fi

    # Конфигурация содержит секрет. Разрешаем чтение только root.
    owner="$(stat -c '%u' "$WOL_CONFIG" 2>/dev/null)"
    permissions="$(stat -c '%a' "$WOL_CONFIG" 2>/dev/null)"
    if [ "$owner" != "0" ] || [ -z "$permissions" ]; then
        wg_error "Неверный владелец конфигурационного файла"
        return 1
    fi

    permission_value=$((0$permissions))
    if [ $((permission_value & 077)) -ne 0 ]; then
        wg_error "Права конфигурации слишком широкие; требуется chmod 600"
        return 1
    fi

    # Файл shell-совместимый и загружается только после проверки root-владельца
    # и отсутствия прав чтения/записи/выполнения для group и other.
    . "$WOL_CONFIG"

    : "${BOT_TOKEN:?BOT_TOKEN не задан}"
    : "${ALLOWED_USER_IDS:?ALLOWED_USER_IDS не задан}"
    : "${TARGET_NAMES:?TARGET_NAMES не задан}"
    : "${TARGET_LABELS:?TARGET_LABELS не задан}"
    : "${TARGET_MACS:?TARGET_MACS не задан}"
    : "${TARGET_IPS:?TARGET_IPS не задан}"
    : "${DEFAULT_TARGETS:?DEFAULT_TARGETS не задан}"

    NETWORK_INTERFACE="${NETWORK_INTERFACE:-br-lan}"

    printf '%s\n' "$BOT_TOKEN" | grep -Eq '^[0-9]+:[A-Za-z0-9_-]+$' || {
        wg_error "BOT_TOKEN имеет неверный формат"
        return 1
    }

    printf '%s\n' "$ALLOWED_USER_IDS" | awk '
        !/^[0-9]+(,[0-9]+)*$/ { exit 1 }
    ' || {
        wg_error "ALLOWED_USER_IDS имеет неверный формат"
        return 1
    }

    printf '%s\n' "$NETWORK_INTERFACE" | grep -Eq '^[A-Za-z0-9_.:-]{1,32}$' || {
        wg_error "NETWORK_INTERFACE имеет неверный формат"
        return 1
    }

    names_count="$(wg_csv_count "$TARGET_NAMES")"
    labels_count="$(wg_csv_count "$TARGET_LABELS")"
    macs_count="$(wg_csv_count "$TARGET_MACS")"
    ips_count="$(wg_csv_count "$TARGET_IPS")"

    if [ "$names_count" -lt 1 ] || [ "$names_count" -gt 20 ] ||
       [ "$names_count" -ne "$labels_count" ] ||
       [ "$names_count" -ne "$macs_count" ] ||
       [ "$names_count" -ne "$ips_count" ]; then
        wg_error "Списки TARGET_NAMES/LABELS/MACS/IPS должны содержать от 1 до 20 парных элементов"
        return 1
    fi

    index=1
    seen=" "
    while [ "$index" -le "$names_count" ]; do
        alias="$(wg_csv_get "$TARGET_NAMES" "$index")"
        label="$(wg_csv_get "$TARGET_LABELS" "$index")"
        mac="$(wg_csv_get "$TARGET_MACS" "$index")"
        ip="$(wg_csv_get "$TARGET_IPS" "$index")"

        printf '%s\n' "$alias" | grep -Eq '^[a-z0-9][a-z0-9-]{0,31}$' || {
            wg_error "Некорректный алиас устройства в TARGET_NAMES"
            return 1
        }

        case "$seen" in
            *" $alias "*) wg_error "Повторяющийся алиас устройства"; return 1 ;;
        esac
        seen="${seen}${alias} "

        [ -n "$label" ] || {
            wg_error "Пустое отображаемое имя устройства"
            return 1
        }

        printf '%s\n' "$mac" | awk '
            !/^[[:xdigit:]][[:xdigit:]](:[[:xdigit:]][[:xdigit:]]){5}$/ { exit 1 }
        ' || {
            wg_error "Некорректный MAC-адрес устройства"
            return 1
        }

        if [ "$ip" != "0" ]; then
            wg_is_valid_ipv4 "$ip" || {
                wg_error "Некорректный IPv4-адрес устройства"
                return 1
            }
        fi

        index=$((index + 1))
    done

    wg_validate_target_list "$DEFAULT_TARGETS" || {
        wg_error "DEFAULT_TARGETS содержит неизвестный или повторяющийся алиас"
        return 1
    }

    # Убедимся, что в allowlist нет пустых или повторяющихся ID.
    seen=" "
    old_ifs="$IFS"
    IFS=','
    for id in $ALLOWED_USER_IDS; do
        case "$seen" in
            *" $id "*) IFS="$old_ifs"; wg_error "Повторяющийся Telegram User ID"; return 1 ;;
        esac
        seen="${seen}${id} "
    done
    IFS="$old_ifs"

    return 0
}

wg_is_allowed_user() {
    local user_id="$1"
    local old_ifs
    local allowed_id

    old_ifs="$IFS"
    IFS=','
    for allowed_id in $ALLOWED_USER_IDS; do
        if [ "$allowed_id" = "$user_id" ]; then
            IFS="$old_ifs"
            return 0
        fi
    done
    IFS="$old_ifs"
    return 1
}
