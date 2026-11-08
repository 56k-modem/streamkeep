FROM python:3.15.2-slim-trixie
LABEL org.opencontainers.image.source=https://github.com/56k-modem/streamkeep
COPY requirements.txt .
RUN apt-get update && apt-get install -y --no-install-recommends procps curl git python3-pip xz-utils \
    && TARBALL="ffmpeg-master-latest-linux64-gpl.tar.xz" \
    && TMP_DIR=$(mktemp -d) \
    && curl -fSL \
        --retry 5 \
        --retry-all-errors \
        --retry-delay 5 \
        --connect-timeout 30 \
        -w 'FFmpeg download: HTTP %{http_code}, bytes %{size_download}\n' \
        -o "${TMP_DIR}/${TARBALL}" \
        "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/${TARBALL}" \
    && tar -tJf "${TMP_DIR}/${TARBALL}" > /dev/null \
    && tar -xf "${TMP_DIR}/${TARBALL}" -C "$TMP_DIR" \
    && EXTRACTED_DIR=$(find "$TMP_DIR" -maxdepth 1 -mindepth 1 -type d | head -1) \
    && install -m 755 "${EXTRACTED_DIR}/bin/ffmpeg" /usr/local/bin/ffmpeg \
    && install -m 755 "${EXTRACTED_DIR}/bin/ffprobe" /usr/local/bin/ffprobe \
    && rm -rf "$TMP_DIR" && \
    rm -rf /var/lib/apt/lists/* && \
    pip install --root-user-action=ignore --upgrade pip && \
    pip install --root-user-action=ignore -r requirements.txt && \
    mkdir /wubby && mkdir /test
ENV TZ=Europe/Budapest
WORKDIR /script
COPY streamlinkcmd-twitch.sh streamlinkcmd-kick.sh streamlinkcmd-test.sh ./
RUN chmod 755 streamlinkcmd-twitch.sh streamlinkcmd-kick.sh streamlinkcmd-test.sh
ENV HOME=/tmp
USER nobody:nogroup
