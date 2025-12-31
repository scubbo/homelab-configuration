# CloudNative-PG: PostgreSQL on Kubernetes

## Overview

[CloudNative-PG](https://cloudnative-pg.io/) is a Kubernetes operator that manages PostgreSQL clusters. It replaces the traditional approach of running PostgreSQL in a standalone container with a Kubernetes-native solution that handles replication, failover, backups, and configuration declaratively.

**Status:** Deployed via Helm chart (`cloudnative-pg` version 0.22.1) in namespace `cnpg-system`

## The Problem It Solves

### Before: Helm Chart-Bundled PostgreSQL

Many Helm charts (Immich, Authentik, etc.) bundle their own PostgreSQL as a subchart. This works, but has drawbacks:

| Aspect | Bundled PostgreSQL | CloudNative-PG |
|--------|-------------------|----------------|
| **Backups** | Manual, often forgotten | Built-in scheduled backups to S3/Azure/GCS |
| **High Availability** | None (single pod) | Automatic failover with streaming replication |
| **Upgrades** | Risky, often manual `pg_dump`/restore | Rolling upgrades, in-place major version upgrades |
| **Monitoring** | DIY | Prometheus metrics out of the box |
| **Storage** | Whatever the subchart defaults to | Explicit StorageClass control |
| **Configuration** | values.yaml overrides | Full PostgreSQL config via CRD |
| **Credentials** | Often hardcoded in values | Auto-generated, stored in Kubernetes Secrets |

### After: CloudNative-PG

With CloudNative-PG, you define a `Cluster` CRD and the operator handles everything:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: my-database
spec:
  instances: 1
  storage:
    storageClass: freenas-iscsi-csi
    size: 5Gi
  bootstrap:
    initdb:
      database: myapp
      owner: myapp
```

The operator:
1. Creates a StatefulSet with the PostgreSQL pod(s)
2. Configures streaming replication (if instances > 1)
3. Generates credentials and stores them in a Secret
4. Exposes Services for read-write and read-only access
5. Monitors health and handles failover

## How It's Deployed Here

### The Operator

Installed via ArgoCD app-of-apps:

```
app-of-apps/cloudnative-pg.jsonnet → Helm chart → cnpg-system namespace
```

The operator watches for `Cluster` resources across all namespaces and manages the actual PostgreSQL pods.

### Application Databases

Individual applications create their own `Cluster` resources. Examples:

**Immich** (`charts/immich/templates/postgres.yaml`):
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: immich-database
spec:
  instances: 1
  imageName: ghcr.io/tensorchord/cloudnative-vectorchord:16.9-0.4.3  # Custom image with vector extensions
  storage:
    storageClass: freenas-iscsi-csi
    size: 10Gi
  bootstrap:
    initdb:
      database: immich
      owner: immich
      postInitSQL:
        - CREATE EXTENSION IF NOT EXISTS vchord CASCADE
        - CREATE EXTENSION IF NOT EXISTS earthdistance CASCADE
```

**Authentik** (`charts/authentik/postgres.yaml`):
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: authentik-database
spec:
  instances: 1
  storage:
    storageClass: freenas-iscsi-csi
    size: 5Gi
  bootstrap:
    initdb:
      database: authentik
      owner: authentik
```

## Auto-Generated Resources

For each `Cluster`, the operator creates:

### Services

| Service Name | Purpose |
|-------------|---------|
| `<cluster>-rw` | Read-write, always points to primary |
| `<cluster>-ro` | Read-only, load-balanced across replicas |
| `<cluster>-r` | Any replica (for read scaling) |

For a single-instance cluster, all three point to the same pod.

### Secrets

| Secret Name | Contents |
|-------------|----------|
| `<cluster>-app` | `username`, `password`, `host`, `port`, `dbname`, `uri`, `jdbc-uri` |
| `<cluster>-superuser` | Superuser credentials (for admin tasks) |

Applications should use the `-app` secret. Example usage in Authentik:

```yaml
volumes:
  - name: postgres-creds
    secret:
      secretName: authentik-database-app
volumeMounts:
  - name: postgres-creds
    mountPath: /postgres-creds
    readOnly: true
```

Then reference via `file:///postgres-creds/password` in the app config.

## Storage Considerations

CloudNative-PG requires block storage (ReadWriteOnce). For this cluster:

- **Use:** `freenas-iscsi-csi` (iSCSI block storage)
- **Avoid:** `freenas-nfs-csi` (NFS doesn't work well with PostgreSQL's fsync requirements)

SQLite on NFS has known issues; PostgreSQL is even more sensitive to storage semantics.

## Common Operations

### Check cluster status

```bash
kubectl get cluster -A
kubectl describe cluster <name> -n <namespace>
```

### View PostgreSQL logs

```bash
kubectl logs -n <namespace> <cluster-name>-1 -f
```

### Connect to database

```bash
# Get password
kubectl get secret <cluster>-app -n <namespace> -o jsonpath='{.data.password}' | base64 -d

# Port-forward
kubectl port-forward -n <namespace> svc/<cluster>-rw 5432:5432

# Connect
psql -h localhost -U <username> -d <dbname>
```

### Manual backup (for testing)

```bash
kubectl exec -n <namespace> <cluster>-1 -- pg_dump -U postgres <dbname> > backup.sql
```

## Current Usage

| Application | Cluster Name | Namespace | Size | Notes |
|-------------|--------------|-----------|------|-------|
| Immich | immich-database | immich | 10Gi | Custom image with vector extensions |
| Authentik | authentik-database | authentik | 5Gi | Standard PostgreSQL |

## Future Improvements

- [ ] Configure scheduled backups to S3/MinIO
- [ ] Add monitoring dashboards to Grafana
- [ ] Consider multi-instance clusters for critical databases
- [ ] Integrate with Vault for credential management

## References

- [CloudNative-PG Documentation](https://cloudnative-pg.io/documentation/)
- [CloudNative-PG Helm Chart](https://github.com/cloudnative-pg/charts)
- [PostgreSQL on Kubernetes Best Practices](https://cloudnative-pg.io/documentation/current/before_you_start/)
