FROM alpine:3.20

RUN apk add --no-cache \
    postgresql16-client \
    openssl \
    coreutils \
    && addgroup -g 1000 -S healthvault \
    && adduser -u 1000 -S healthvault -G healthvault \
    && mkdir -p /backups \
    && chown healthvault:healthvault /backups

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
