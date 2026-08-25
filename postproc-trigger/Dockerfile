FROM docker:cli
LABEL org.opencontainers.image.source https://github.com/56k-modem/streamkeep
COPY watch-postproc.sh /watch-postproc.sh
RUN chmod +x /watch-postproc.sh
ENTRYPOINT ["/bin/sh", "/watch-postproc.sh"]
