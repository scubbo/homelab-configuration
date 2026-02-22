# k3s External PostgreSQL Datastore

This document describes the external PostgreSQL database that serves as the k3s cluster's datastore (replacing the default embedded etcd/SQLite).

## Configuration Snapshots

This directory contains snapshots of the configuration files deployed on epsilon. These may drift from the live configuration - always check epsilon for the authoritative version.

| File | Source on epsilon |
|------|-------------------|
| [docker-compose.yaml](docker-compose.yaml) | `/home/scubbo/k3s-ha-postgres/docker-compose.yaml` |
| [backup.sh](backup.sh) | `/home/scubbo/k3s-ha-postgres/backup.sh` |
| [k3s-postgres-docker.service](k3s-postgres-docker.service) | `/etc/systemd/system/k3s-postgres-docker.service` |
| [crontab-entry.txt](crontab-entry.txt) | `crontab -l` (scubbo user) |

## Architecture

The k3s cluster uses PostgreSQL as its datastore via the [kine](https://github.com/k3s-io/kine) adapter. This provides:
- Standard SQL database for cluster state
- Easier backup/restore compared to embedded etcd
- Familiar tooling (pg_dump, psql, etc.)

```
┌─────────────────────────────────────────────────────────────┐
│                      epsilon.avril                          │
│                                                             │
│  ┌─────────────────┐        ┌─────────────────────────────┐ │
│  │    k3s server   │◄──────►│   PostgreSQL (Docker)       │ │
│  │   (systemd)     │        │   k3s-ha-postgres-pg-1      │ │
│  └─────────────────┘        │   Port: 5432                │ │
│                             │   Database: kubernetes      │ │
│                             └─────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                                        │
                                        │ pg_dump (cron)
                                        ▼
                    ┌─────────────────────────────────────┐
                    │         galactus-nfs (NAS)          │
                    │  /backups/k3s-ha-backups/*.sql      │
                    └─────────────────────────────────────┘
```

## Components on epsilon.avril

| Component | Location |
|-----------|----------|
| Docker Compose config | `/home/scubbo/k3s-ha-postgres/docker-compose.yaml` |
| PostgreSQL data | `/home/scubbo/k3s-ha-postgres-data/` |
| Backup script | `/home/scubbo/k3s-ha-postgres/backup.sh` |
| Systemd service | `/etc/systemd/system/k3s-postgres-docker.service` |

### Docker Compose Configuration

```yaml
services:
  pg:
    image: postgres
    ports:
      - "5432:5432"
    environment:
      POSTGRES_PASSWORD: <stored in docker-compose.yaml>
    volumes:
      - /home/scubbo/k3s-ha-postgres-data:/var/lib/postgresql/data
```

### Systemd Service

The PostgreSQL container is managed by systemd:

```bash
# Check status
systemctl status k3s-postgres-docker

# View logs
journalctl -u k3s-postgres-docker -f
```

## Backup

### Schedule

Backups run via cron every 5 days at 5:00 AM:

```cron
0 5 */5 * * /home/scubbo/k3s-ha-postgres/backup.sh 2>&1 | logger -t k3s-ha-postgres-backup
```

### Backup Location

- **Destination:** `/mnt/galactus-nfs/backups/k3s-ha-backups/`
- **Format:** SQL dumps named with ISO 8601 timestamps (e.g., `2026-02-22T13:47:49.sql`)
- **Retention:** 90 days (automatic cleanup)
- **Size:** ~70-80 MB per backup

### Manual Backup

```bash
# Run backup manually
/home/scubbo/k3s-ha-postgres/backup.sh

# Check recent backups
ls -lah /mnt/galactus-nfs/backups/k3s-ha-backups/ | tail -10
```

### Backup Script Features

The backup script (`/home/scubbo/k3s-ha-postgres/backup.sh`) includes:
- Error handling with `set -euo pipefail`
- Backup validation (checks file is non-empty and contains expected content)
- Automatic cleanup of backups older than 90 days
- Logging via syslog

## Restore Procedure

This procedure was tested on 2026-02-22.

### Prerequisites

- SSH access to epsilon
- Docker installed on the target machine
- Access to NAS backup location

### Steps

1. **Identify the backup to restore:**
   ```bash
   ls -lah /mnt/galactus-nfs/backups/k3s-ha-backups/
   # Choose a backup file, e.g., 2026-02-21T05:00:01
   ```

2. **Stop k3s (if doing in-place restore):**
   ```bash
   sudo systemctl stop k3s
   ```

3. **Create a fresh PostgreSQL container (or use existing):**
   ```bash
   # For testing/new instance:
   docker run -d --name k3s-pg-restore \
     -e POSTGRES_PASSWORD=<password> \
     -p 5432:5432 \
     -v /path/to/data:/var/lib/postgresql/data \
     postgres:17

   # Wait for postgres to be ready
   docker exec k3s-pg-restore pg_isready -U postgres
   ```

4. **Create the database:**
   ```bash
   docker exec k3s-pg-restore createdb -U postgres kubernetes
   ```

5. **Restore the backup:**
   ```bash
   BACKUP_FILE="/mnt/galactus-nfs/backups/k3s-ha-backups/2026-02-21T05:00:01"
   docker exec -i k3s-pg-restore psql -U postgres -d kubernetes < "$BACKUP_FILE"
   ```

6. **Verify the restore:**
   ```bash
   # Check row count
   docker exec k3s-pg-restore psql -U postgres -d kubernetes \
     -c "SELECT COUNT(*) FROM kine;"

   # Check table structure
   docker exec k3s-pg-restore psql -U postgres -d kubernetes \
     -c "\d kine"
   ```

7. **Update k3s configuration (if changing PostgreSQL endpoint):**
   - Edit `/etc/rancher/k3s/config.yaml` if needed
   - Restart k3s: `sudo systemctl start k3s`

## Monitoring & Troubleshooting

### Check Database Health

```bash
# Connect to database
docker exec -it k3s-ha-postgres-pg-1 psql -U postgres -d kubernetes

# Check row count
SELECT COUNT(*) FROM kine;

# Check table size
SELECT pg_size_pretty(pg_total_relation_size('kine'));

# Recent entries
SELECT id, name, created FROM kine ORDER BY id DESC LIMIT 10;
```

### Check Backup Logs

```bash
# View backup logs
journalctl -t k3s-ha-postgres-backup

# Check last backup ran successfully
ls -la /mnt/galactus-nfs/backups/k3s-ha-backups/ | tail -3
```

### Container Status

```bash
# Check container is running
docker ps | grep k3s-ha-postgres

# View container logs
docker logs k3s-ha-postgres-pg-1 --tail 50
```

## Disaster Recovery

In case of complete epsilon failure:

1. **Provision a new server** with Docker and k3s prerequisites
2. **Mount NAS** at `/mnt/galactus-nfs` (or copy backup files locally)
3. **Follow the Restore Procedure** above to create a new PostgreSQL instance
4. **Install k3s** with the `--datastore-endpoint` pointing to the new PostgreSQL
5. **Apply ArgoCD manifests** to restore cluster state from git

Note: The cluster state (deployments, services, etc.) is stored in PostgreSQL. Application data stored in PVCs is separate and managed by TrueNAS/democratic-csi.
