FROM python:3.12-slim
LABEL org.opencontainers.image.source https://github.com/56k-modem/streamkeep
RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg fonts-dejavu-core bash && \
    rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY Misc-Fixed-7x13.ttf /usr/share/fonts/truetype/
RUN fc-cache -fv
COPY vcsi-run.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/vcsi-run.sh
ENV TS_FOLDER=/input \
    JPG_FOLDER=/output \
    FONT_PATH=/usr/share/fonts/truetype/Misc-Fixed-7x13.ttf
VOLUME ["/input", "/output"]
ENTRYPOINT ["/usr/local/bin/vcsi-run.sh"]
