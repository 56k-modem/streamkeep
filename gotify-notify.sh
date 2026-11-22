#!/bin/bash

gotify_notify() {
    local title="$1"
    local message="$2"

    if [[ -z "${GOTIFY_URL:-}" || -z "${GOTIFY_APP_TOKEN:-}" ]]; then
        if [[ -n "${GOTIFY_URL:-}${GOTIFY_APP_TOKEN:-}" ]]; then
            printf 'Gotify notification skipped for "%s": set GOTIFY_URL and GOTIFY_APP_TOKEN\n' "$title" >&2
        fi
        return 0
    fi

    if ! curl --silent --fail --max-time 5 --output /dev/null \
        --header "X-Gotify-Key: ${GOTIFY_APP_TOKEN}" \
        --data-urlencode "title=${title}" \
        --data-urlencode "message=${message}" \
        --url "$GOTIFY_URL"; then
        printf 'Gotify delivery failed for "%s"\n' "$title" >&2
    fi
}
