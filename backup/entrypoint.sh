#!/bin/sh
# Fix ownership on mounted volumes (runs as root initially)
chown -R healthvault:healthvault /backups 2>/dev/null || true

# Drop to unprivileged user for the actual backup loop
exec su -s /bin/sh healthvault -c "while true; do /usr/local/bin/backup.sh; sleep \${BACKUP_INTERVAL:-86400}; done"
