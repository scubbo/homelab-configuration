#!/bin/bash
# Snapshot of epsilon:/home/scubbo/k3s-ha-postgres/backup.sh
# Last updated: 2026-02-22
set -euo pipefail

# Configuration
BACKUP_DIR="/mnt/galactus-nfs/backups/k3s-ha-backups"
CONTAINER="k3s-ha-postgres-pg-1"
DATABASE="kubernetes"
RETENTION_DAYS=90  # Keep ~18 backups at 5-day intervals

DATE=$(date "+%Y-%m-%dT%H:%M:%S")
BACKUP_FILE="$BACKUP_DIR/$DATE.sql"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Create backup
echo "Starting backup of $DATABASE at $DATE"
if docker exec "$CONTAINER" pg_dump -U postgres -d "$DATABASE" > "$BACKUP_FILE"; then
    # Verify backup file is not empty and contains expected content
    if [ -s "$BACKUP_FILE" ] && grep -q "CREATE TABLE public.kine" "$BACKUP_FILE"; then
        echo "Backup successful: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"

        # Clean up old backups
        find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete
        echo "Cleaned up backups older than $RETENTION_DAYS days"
    else
        echo "ERROR: Backup file appears to be empty or invalid" >&2
        rm -f "$BACKUP_FILE"
        exit 1
    fi
else
    echo "ERROR: pg_dump failed" >&2
    rm -f "$BACKUP_FILE"
    exit 1
fi
