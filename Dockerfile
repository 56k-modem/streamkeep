FROM python:3.14.8-slim-bookworm
LABEL org.opencontainers.image.source=https://github.com/56k-modem/streamkeep
COPY requirements.txt .
RUN groupadd -g 1000 csd && useradd -m -u 1000 -g csd csd && \
    apt-get update && apt-get install -y --no-install-recommends procps curl git python3-pip xz-utils \
    && TARBALL="ffmpeg-master-latest-linux64-gpl.tar.xz" \
    && TMP_DIR=$(mktemp -d) \
    && curl -sS -L -o "${TMP_DIR}/${TARBALL}" "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/${TARBALL}" \
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
RUN chown csd:csd streamlinkcmd-twitch.sh streamlinkcmd-kick.sh streamlinkcmd-test.sh && \
    chmod +x streamlinkcmd-twitch.sh streamlinkcmd-kick.sh streamlinkcmd-test.sh
USER csd
