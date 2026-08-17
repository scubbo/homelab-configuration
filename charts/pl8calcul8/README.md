# pl8calcul8

Backup server for the [pl8calcul8](https://github.com/scubbo/pl8calcul8)
weightlifting tracker Android app. Stores JSON snapshots of the app's
database and serves the most recent one back for restore.

## Endpoints

* `GET /healthz` - liveness/readiness, no auth
* `POST /backup` - store a snapshot (bearer token)
* `GET /restore` - return the newest snapshot (bearer token)

## Setup

1. Create the token secret - see `secret.example.yaml`.
2. The image is built by GitHub Actions in the app repo and published to
   `ghcr.io/scubbo/pl8calcul8`; pin `image.tag` in `values.yaml` to a
   `sha-<gitsha>` tag to deploy a new version.

## Exposure

* Internal: `pl8calcul8.avril` (Traefik ingress, external-dns).
* External: `pl8calcul8.scubbo.org` via the Cloudflare tunnel
  (entry in `charts/cloudflared/values.yaml`).
