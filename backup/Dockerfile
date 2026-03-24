FROM alpine:3.20

RUN apk add --no-cache \
    postgresql16-client \
    openssl \
    coreutils \
    && addgroup -g 1000 -S healthvault \
    && adduser -u 1000 -S healthvault -G healthvault

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

USER healthvault:healthvault

ENTRYPOINT ["sh", "-c"]
CMD ["while true; do /usr/local/bin/backup.sh; sleep ${BACKUP_INTERVAL:-86400}; done"]
