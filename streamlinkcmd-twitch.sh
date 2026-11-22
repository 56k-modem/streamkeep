#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/gotify-notify.sh"

echo "*** Container starting"
RID=$(cat /proc/sys/kernel/random/uuid)
RECORDING="/wubby/twitch-${RID}"
FINAL_VOD="/wubby/twitch-${RID:0:8}.mp4"

exec {log_fd}> >(
    notification_pid=
    while IFS= read -r line; do
        printf '%s\n' "$line" >&2
        if [[ "$line" == *"Opening stream"* && -z "$notification_pid" ]]; then
            touch "${RECORDING}.recording"
            gotify_notify \
                "Twitch recording started" \
                "Started recording paymoneywubby on Twitch (recording ID: ${RID})." &
            notification_pid=$!
        fi
    done
    if [[ -n "$notification_pid" ]]; then
        wait "$notification_pid"
    fi
)
log_pid=$!
streamlink --retry-streams 5 --stdout "--twitch-api-header=Authorization=OAuth ${TWITCH_OAUTH:?TWITCH_OAUTH env var required}" twitch.tv/paymoneywubby best 2>&"$log_fd" \
    | ffmpeg -hide_banner -nostats -i pipe:0 -c copy -map 0:v -map 0:a -movflags +faststart "${RECORDING}.mp4"
exec {log_fd}>&-
wait "$log_pid"

rm -f "${RECORDING}.recording"
if [[ -s "${RECORDING}.mp4" ]] && mv "${RECORDING}.mp4" "$FINAL_VOD"; then
    gotify_notify \
        "Twitch recording finished" \
        "Finished recording paymoneywubby on Twitch (recording ID: ${RID})."
fi
