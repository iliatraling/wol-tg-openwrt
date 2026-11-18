#!/bin/sh
# Действия Wake-on-LAN, проверка ping и обработка команд.

WOL_COOLDOWN_SECONDS=15
WOL_COOLDOWN_FILE="/tmp/wol-gateway.last-wake"

wg_send_magic_packet() {
    local mac="$1"

    command -v etherwake >/dev/null 2>&1 || {
        wg_error "Утилита etherwake не установлена"
        return 1
    }

    # MAC предварительно проверен при загрузке конфигурации.
    etherwake -i "$NETWORK_INTERFACE" "$mac" >/dev/null 2>&1
}

wg_wake_targets() {
    local aliases="$1"
    local rest
    local alias
    local now
    local last
    local result
    local sent
    local failed
    local label
    local mac

    now="$(date +%s)"
    last=0
    if [ -r "$WOL_COOLDOWN_FILE" ]; then
        last="$(cat "$WOL_COOLDOWN_FILE" 2>/dev/null)"
        case "$last" in
            ''|*[!0-9]*) last=0 ;;
        esac
    fi

    if [ $((now - last)) -lt "$WOL_COOLDOWN_SECONDS" ]; then
        printf '⏳ Повторный WOL временно ограничен. Подождите %s секунд.' "$WOL_COOLDOWN_SECONDS"
        return 0
    fi

    # Проверка всех алиасов выполняется до отправки первого пакета.
    if ! wg_validate_target_list "$aliases"; then
        printf 'Неизвестное устройство или некорректный список алиасов.'
        return 0
    fi

    printf '%s\n' "$now" > "$WOL_COOLDOWN_FILE"

    result="Команда /wake получена"
    sent=0
    failed=0
    rest="$aliases"

    while :; do
        case "$rest" in
            *,*) alias="${rest%%,*}"; rest="${rest#*,}" ;;
            *) alias="$rest"; rest="" ;;
        esac

        wg_find_target "$alias"
        label="$TARGET_LABEL"
        mac="$TARGET_MAC"

        if wg_send_magic_packet "$mac"; then
            result="$result\n✅ Magic Packet отправлен: $label"
            sent=$((sent + 1))
            wg_log "Magic Packet отправлен для алиаса $alias"
        else
            result="$result\n❌ Не удалось отправить Magic Packet: $label"
            failed=$((failed + 1))
            wg_error "Не удалось отправить Magic Packet для алиаса $alias"
        fi

        [ -n "$rest" ] || break
    done

    if [ "$sent" -eq 0 ] && [ "$failed" -eq 0 ]; then
        result="$result\nУстройства не выбраны."
    fi

    printf '%b' "$result"
}

wg_status_targets() {
    local aliases="$1"
    local rest
    local alias
    local label
    local ip
    local result

    if ! wg_validate_target_list "$aliases"; then
        printf 'Неизвестное устройство или некорректный список алиасов.'
        return 0
    fi

    result="Статус устройств:"
    rest="$aliases"

    while :; do
        case "$rest" in
            *,*) alias="${rest%%,*}"; rest="${rest#*,}" ;;
            *) alias="$rest"; rest="" ;;
        esac

        wg_find_target "$alias"
        label="$TARGET_LABEL"
        ip="$TARGET_IP"

        if [ "$ip" = "0" ]; then
            result="$result\n⚪ $label — IP не указан, проверка пропущена."
        elif ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
            result="$result\n🟢 $label ($ip) — доступен."
        else
            result="$result\n🔴 $label ($ip) — недоступен по ping."
        fi

        [ -n "$rest" ] || break
    done

    printf '%b' "$result"
}

wg_help_text() {
    cat <<'HELP'
Доступные команды:
/wake — включить устройства по умолчанию
/wake home — включить одно устройство
/wake home,work — включить несколько устройств
/status — проверить устройства по умолчанию
/status home — проверить одно устройство
/status home,work — проверить несколько устройств
/help — показать эту справку

Для /status устройству нужен IP-адрес. Значение IP=0 отключает проверку ping.
HELP
}

wg_handle_command() {
    local chat_id="$1"
    local text="$2"
    local command
    local arguments
    local response

    # Не интерпретируем текст как shell-команду. Разбираем только первый токен.
    text="$(printf '%s' "$text" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$text" ] || return 0

    command="${text%% *}"
    arguments=""
    if [ "$text" != "$command" ]; then
        arguments="${text#"$command"}"
        arguments="$(printf '%s' "$arguments" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    fi

    case "$command" in
        /wake|/wake@*)
            if [ -z "$arguments" ]; then
                arguments="$DEFAULT_TARGETS"
            fi
            case "$arguments" in
                *[!a-z0-9,-]*)
                    response="Формат: /wake home или /wake home,work"
                    ;;
                *)
                    response="$(wg_wake_targets "$arguments")"
                    ;;
            esac
            ;;
        /status|/status@*)
            if [ -z "$arguments" ]; then
                arguments="$DEFAULT_TARGETS"
            fi
            case "$arguments" in
                *[!a-z0-9,-]*)
                    response="Формат: /status home или /status home,work"
                    ;;
                *)
                    response="$(wg_status_targets "$arguments")"
                    ;;
            esac
            ;;
        /help|/help@*)
            if [ -n "$arguments" ]; then
                response="Команда /help не принимает аргументы."
            else
                response="$(wg_help_text)"
            fi
            ;;
        *)
            response="Неизвестная команда. Используйте /help."
            ;;
    esac

    tg_send_message "$chat_id" "$response" || {
        wg_error "Не удалось отправить ответ в Telegram"
        return 1
    }
    return 0
}
