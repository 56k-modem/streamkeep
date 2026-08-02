#!/bin/bash

apprise_notify() {
    local TITLE="$1"
    local BODY="$2"
    : "${APPRISE_URL:?APPRISE_URL env var required}"

    python3 -c '
import json
import os
import sys

print(json.dumps({
    "urls": os.environ["APPRISE_URL"],
    "title": sys.argv[1],
    "body": sys.argv[2],
}))
' "$TITLE" "$BODY" |
        curl -fsS -m 10 --retry 5 \
            -H "Content-Type: application/json" \
            --data-binary @- \
            "${APPRISE_API_URL:?APPRISE_API_URL env var required}"
}

echo "*** Container starting"
RID=$(cat /proc/sys/kernel/random/uuid)
streamlink --retry-streams 5 --stdout "--twitch-api-header=Authorization=OAuth ${TWITCH_OAUTH:?TWITCH_OAUTH env var required}" twitch.tv/paymoneywubby best \
  2> >(
    while IFS= read -r line; do
      printf '%s\n' "$line" >&2
      if [[ "$line" == *"Opening stream"* ]]; then
        touch "/wubby/twitch-${RID}.recording"
        curl -fsS -m 10 --retry 5 "https://hc-ping.com/${HC_UUID:?HC_UUID env var required}/start?rid=$RID"
        curl -fsS -m 10 --retry 5 "${HC_LOCAL_PING_URL:?HC_LOCAL_PING_URL env var required}/start?rid=$RID"
        apprise_notify \
            "Twitch recording started" \
            "Started recording paymoneywubby on Twitch (recording ID: ${RID})."
      fi
    done
  ) \
  | ffmpeg -hide_banner -nostats -i pipe:0 -c copy -map 0:v -map 0:a -movflags +faststart "/wubby/twitch-${RID}.mp4"
wait
rm -f "/wubby/twitch-${RID}.recording"
mv "/wubby/twitch-${RID}.mp4" "/wubby/twitch-$(echo "$RID" | cut -c1-8).mp4"
lengthscript() {
    shopt -s nullglob
    cd /wubby
    while IFS= read -r FILE; do
        echo "$FILE" $(ffprobe -i "$FILE" -show_entries format=duration -v quiet -of csv="p=0" -sexagesimal | sed 's/.......$//')
    done < <(ls -tr twitch*.mp4 2>/dev/null)
}
lengthscript > /tmp/vodsdata.tmp
vodsdata=$(cat /tmp/vodsdata.tmp)
for url in \
  "https://hc-ping.com/${HC_UUID}?rid=$RID" \
  "${HC_LOCAL_PING_URL}?rid=$RID"; do
  curl -fsS -m 10 --retry 5 --data-raw "$vodsdata" "$url"
done
apprise_notify \
    "Twitch recording finished" \
    "Finished recording paymoneywubby on Twitch (recording ID: ${RID}).

${vodsdata}"
rm /tmp/vodsdata.tmp
