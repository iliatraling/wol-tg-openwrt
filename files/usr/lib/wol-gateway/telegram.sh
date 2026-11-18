#!/bin/sh
# Вызовы Telegram Bot API. Токен передаётся curl через stdin-конфигурацию,
# поэтому не появляется в аргументах процесса и системном списке процессов.

tg_get_updates() {
    local offset="$1"
    local timeout="$2"
    local query

    query="timeout=$timeout&allowed_updates=%5B%22message%22%5D"
    if [ -n "$offset" ]; then
        query="offset=$offset&$query"
    fi

    printf 'url = "https://api.telegram.org/bot%s/getUpdates?%s"\n' "$BOT_TOKEN" "$query" |
        curl --config - --silent --show-error --fail \
            --connect-timeout 10 --max-time 40
}

tg_send_message() {
    local chat_id="$1"
    local message="$2"

    # chat_id и текст не являются секретами; токен остаётся в stdin curl.
    printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$BOT_TOKEN" |
        curl --config - --silent --show-error --fail \
            --connect-timeout 10 --max-time 20 \
            --data-urlencode "chat_id=$chat_id" \
            --data-urlencode "text=$message" >/dev/null
}
