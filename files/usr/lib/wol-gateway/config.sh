#!/bin/sh
# Load and validate WOL Gateway configuration.

WOL_CONFIG="${WOL_CONFIG:-/etc/wol-gateway.env}"
wg_logging_enabled() {
    # Подробное логирование включено по умолчанию; состояние хранится в UCI.
    [ "$(uci -q get wol-gateway.main.logging 2>/dev/null)" != "0" ]
}

wg_log() {
    # Обычные сообщения идут только в RAM-журнал OpenWrt.
    local message="$1"
    wg_logging_enabled || return 0
    logger -t wol-gateway "$message" 2>/dev/null
}

wg_error() {
    # Ошибки не отключаются переключателем подробного логирования.
    logger -p daemon.err -t wol-gateway "ERROR: $1" 2>/dev/null
}

wg_csv_count() {
    # Count CSV items without evaluating their contents.
    printf '%s\n' "$1" | awk -F ',' '{ print NF }'
}

wg_csv_get() {
    # Return a list item by its one-based index.
    printf '%s\n' "$1" | awk -F ',' -v idx="$2" '{
        value = $idx
        gsub(/^[ \t]+|[ \t]+$/, "", value)
        sub(/\r$/, "", value)
        print value
    }'
}

wg_is_valid_ipv4() {
    # Validate IPv4 without performing DNS lookups.
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
    # Find a device by alias and populate TARGET_* variables.
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
    # Check that every alias exists and is not repeated in the request.
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
    local group_other_permissions
    local metadata
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
        wg_error "Configuration file is missing or is a symbolic link"
        return 1
    fi

    # The configuration contains a secret. Only root may own and access it.
    # Use BusyBox ls because the OpenWrt image may not include the stat applet.
    metadata="$(ls -ldn "$WOL_CONFIG" 2>/dev/null)"
    owner="$(printf '%s\n' "$metadata" | awk 'NR == 1 { print $3 }')"
    group_other_permissions="$(printf '%s\n' "$metadata" | awk 'NR == 1 { print substr($1, 5, 6) }')"

    if [ "$owner" != "0" ] || [ "$group_other_permissions" != "------" ]; then
        wg_error "Configuration file must be owned by root and have mode 600 or stricter"
        return 1
    fi

    # Load the shell-compatible file only after validating its owner and permissions.
    . "$WOL_CONFIG"

    : "${BOT_TOKEN:?BOT_TOKEN is not set}"
    : "${ALLOWED_USER_IDS:?ALLOWED_USER_IDS is not set}"
    : "${TARGET_NAMES:?TARGET_NAMES is not set}"
    : "${TARGET_LABELS:?TARGET_LABELS is not set}"
    : "${TARGET_MACS:?TARGET_MACS is not set}"
    : "${TARGET_IPS:?TARGET_IPS is not set}"
    : "${DEFAULT_TARGETS:?DEFAULT_TARGETS is not set}"

    NETWORK_INTERFACE="${NETWORK_INTERFACE:-br-lan}"

    printf '%s\n' "$BOT_TOKEN" | grep -Eq '^[0-9]+:[A-Za-z0-9_-]+$' || {
        wg_error "BOT_TOKEN has an invalid format"
        return 1
    }

    printf '%s\n' "$ALLOWED_USER_IDS" | awk '
        !/^[0-9]+(,[0-9]+)*$/ { exit 1 }
    ' || {
        wg_error "ALLOWED_USER_IDS has an invalid format"
        return 1
    }

    printf '%s\n' "$NETWORK_INTERFACE" | grep -Eq '^[A-Za-z0-9_.:-]{1,32}$' || {
        wg_error "NETWORK_INTERFACE has an invalid format"
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
        wg_error "TARGET_NAMES/LABELS/MACS/IPS must contain 1 to 20 matching items"
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
            wg_error "Invalid device alias in TARGET_NAMES"
            return 1
        }

        case "$seen" in
            *" $alias "*) wg_error "Duplicate device alias"; return 1 ;;
        esac
        seen="${seen}${alias} "

        [ -n "$label" ] || {
            wg_error "Device display label is empty"
            return 1
        }

        printf '%s\n' "$mac" | awk '
            !/^[[:xdigit:]][[:xdigit:]](:[[:xdigit:]][[:xdigit:]]){5}$/ { exit 1 }
        ' || {
            wg_error "Invalid device MAC address"
            return 1
        }

        if [ "$ip" != "0" ]; then
            wg_is_valid_ipv4 "$ip" || {
                wg_error "Invalid device IPv4 address"
                return 1
            }
        fi

        index=$((index + 1))
    done

    wg_validate_target_list "$DEFAULT_TARGETS" || {
        wg_error "DEFAULT_TARGETS contains an unknown or duplicate alias"
        return 1
    }

    # Reject empty or duplicate Telegram user IDs in the allowlist.
    seen=" "
    old_ifs="$IFS"
    IFS=','
    for id in $ALLOWED_USER_IDS; do
        case "$seen" in
            *" $id "*) IFS="$old_ifs"; wg_error "Duplicate Telegram User ID"; return 1 ;;
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
