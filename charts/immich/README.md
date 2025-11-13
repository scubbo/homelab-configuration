# Setup Requirements

## NFS Volume Configuration

The Immich application stores its library data on an NFS volume mounted from `galactus.avril` at `/mnt/low-resiliency-with-read-cache/immich-library/`.

Immich runs as UID/GID 1000 inside the container (mapped to `k8s-user` on the NFS server). The NFS directory must be owned by this user and properly exported to allow Immich to create the required directory structure.

On the NFS server (`galactus`), perform the following setup:

1. Ensure the directory has the correct ownership:
   ```bash
   chown -R 1000:1000 /mnt/low-resiliency-with-read-cache/immich-library/
   ```

2. Add the directory to `/etc/exports` with the appropriate mapping:
   ```bash
   /mnt/low-resiliency-with-read-cache/immich-library -mapall="k8s-user":"k8s-user"
   ```

3. Restart the NFS service to apply the changes:
   ```bash
   service nfsd restart
   ```

## Database Extensions

Immich requires the CloudNative-PG operator to be installed and configured with the VectorChord PostgreSQL extension. The database cluster definition in `templates/postgres.yaml` uses the `ghcr.io/tensorchord/cloudnative-vectorchord` image which includes the necessary extensions.

The extensions (`vchord` and `earthdistance`) are created automatically via the `postInitSQL` configuration. If they fail to be created automatically, they can be created manually:

```bash
kubectl exec -n immich immich-database-1 -c postgres -- psql -U postgres -d immich -c 'CREATE EXTENSION IF NOT EXISTS vchord CASCADE'
kubectl exec -n immich immich-database-1 -c postgres -- psql -U postgres -d immich -c 'CREATE EXTENSION IF NOT EXISTS earthdistance CASCADE'
```
