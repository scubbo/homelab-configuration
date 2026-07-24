# dropbox-backup — scheduled Dropbox backups to the NAS

Takes a daily, encrypted, deduplicated backup of the entire Dropbox account onto the
`galactus` NAS, keeping a decaying history of snapshots.

```
Dropbox ──(rclone sync)──► /data/mirror ──(restic backup)──► /data/repo
          nightly deltas    1× plain copy   dedup+encrypted    snapshot history
                                                               + forget/prune retention
```

Both directories live under a single NFS volume on
`galactus.avril:/mnt/high-resiliency/manual-nfs/backups/dropbox-backups`.

## How it works

A daily Kubernetes `CronJob` (`03:17`, tunable via `schedule` in `values.yaml`) runs two
ordered steps in one pod:

1. **`rclone-sync` (init container)** mirrors Dropbox into `/data/mirror`. The mirror is
   persistent, so only changed files are transferred each night. If the sync fails, the pod
   fails and step 2 never runs — a broken sync can never snapshot a half-mirrored tree.
2. **`restic-backup` (main container)** snapshots `/data/mirror` into the restic repo at
   `/data/repo`, then runs `restic forget --prune` to enforce retention, then `restic check`
   to verify repo integrity. The repo self-initialises on first run.

### Why two tools

restic can't read Dropbox as a *source*, so rclone pulls the data to disk first; restic then
provides deduplication (near-identical daily snapshots don't grow storage linearly),
encryption at rest, and native decaying retention.

### Retention

Set in `values.yaml` under `retention:` and passed to `restic forget`:

| Setting | Default | Meaning (restic buckets, not "exactly N days ago") |
|---|---|---|
| `daily`   | 7  | keep the last snapshot of each of the last 7 days with snapshots |
| `weekly`  | 4  | ...of each of the last 4 weeks |
| `monthly` | 12 | ...of each of the last 12 months |
| `yearly`  | 3  | ...of each of the last 3 years |

## Setup

### 1. NFS directory on galactus

The job runs as UID/GID 1000 (mapped to `k8s-user` on the NAS). Create and own the dataset,
and export it with the `k8s-user` mapping (same convention as the immich chart):

```bash
mkdir -p /mnt/high-resiliency/manual-nfs/backups/dropbox-backups
chown -R 1000:1000 /mnt/high-resiliency/manual-nfs/backups/dropbox-backups
# in /etc/exports:
#   /mnt/high-resiliency/manual-nfs/backups/dropbox-backups -mapall="k8s-user":"k8s-user"
service nfsd restart
```

### 2. rclone Dropbox token

On any machine with a browser and rclone installed (**not** in the repo directory):

```bash
# Recommended: create your own Dropbox API app first (Dropbox rate-limits rclone's
# shared client ID hard on large syncs) at https://www.dropbox.com/developers/apps
# — "Scoped access", "Full Dropbox", then note the App key + App secret.

rclone config          # create a remote named `dropbox`, type `dropbox`,
                       # supplying your app key/secret and completing the OAuth flow
rclone config file     # shows the path to the generated rclone.conf
cp "$(rclone config file | tail -1)" /tmp/rclone.conf
```

`/tmp/rclone.conf` should contain a `[dropbox]` section with a `token = {...}` line that
includes a `refresh_token` (that's what keeps the backup working long-term without
re-authing).

### 3. Create the Secret (never committed)

The restic password is not fetched from anywhere — it's a passphrase you invent. Generate one
and **save it to your password manager first**, because you'll need it to restore the repo onto
a fresh system if this cluster is ever gone (which is the whole point of having the backup):

```bash
RESTIC_PW="$(openssl rand -base64 32)"; echo "$RESTIC_PW"   # copy this into your password manager
```

Then create the Secret, reusing that same value:

```bash
kubectl create namespace dropbox-backup
kubectl create secret generic dropbox-backup-secrets \
  --namespace dropbox-backup \
  --from-file=rclone.conf=/tmp/rclone.conf \
  --from-literal=restic-password="$RESTIC_PW"
```

Lose this password and the repo is unrecoverable — restic has no backdoor. See
`secret.example.yaml` for the expected shape.

## Restoring

Backups are only real if you can restore them. Spin up a throwaway pod with the restic image,
the same repo volume, and the same Secret:

```bash
kubectl run restic-restore -n dropbox-backup --rm -it --restart=Never \
  --image=restic/restic:0.17.3 \
  --overrides='
{
  "spec": {
    "securityContext": {"runAsUser": 1000, "fsGroup": 1000},
    "containers": [{
      "name": "restic",
      "image": "restic/restic:0.17.3",
      "stdin": true, "tty": true, "command": ["/bin/sh"],
      "env": [
        {"name": "RESTIC_REPOSITORY", "value": "/data/repo"},
        {"name": "RESTIC_PASSWORD", "valueFrom": {"secretKeyRef": {"name": "dropbox-backup-secrets", "key": "restic-password"}}}
      ],
      "volumeMounts": [{"name": "data", "mountPath": "/data"}]
    }],
    "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "dropbox-backup-pvc"}}]
  }
}'
```

Then inside the pod:

```bash
restic snapshots                              # list snapshots
restic restore <snapshot-id> --target /data/restore   # or `latest`
```

## Observability

An unchecked backup is a broken backup, so the chart ships three things that watch it: an
exporter that publishes repo health as metrics, a weekly restore drill that *proves*
restorability, and a set of alerts wired to Telegram.

### restic-exporter

The nightly backup is a short-lived CronJob with nothing to scrape, so a long-lived
`restic-exporter` Deployment (`exporter.enabled`) opens the repo once an hour
(`exporter.refreshInterval`) and exposes metrics scraped via a `ServiceMonitor`. It mounts the
repo over its own inline NFS volume — not the `ReadWriteOnce` PVC — so it need not co-locate on
the backup pod's node. Its reads only take a *shared* restic lock; the nightly `forget --prune`
takes an exclusive one, so every nightly restic command uses `--retry-lock 5m` to wait out the
overlap instead of erroring.

Key metrics:

| Metric | Meaning |
|---|---|
| `restic_backup_timestamp`   | Unix time of the last snapshot — the primary health signal (its age) |
| `restic_snapshots_total`    | number of snapshots in the repo |
| `restic_size_total`         | on-disk repo size (dedup+compressed) — the growth/capacity trend |
| `restic_check_success`      | `1` if the hourly `restic check` passed, `0` if the repo failed integrity |

A Grafana dashboard (`dashboard.enabled`, ConfigMap labelled `grafana_dashboard: "1"`, titled
**Dropbox Backup**) charts all of the above plus the nightly-job and restore-drill last-success
ages.

### Restore drill

`restic check` proves repo *integrity*; it does **not** prove the data can actually be restored.
A weekly `restore-drill` CronJob (`restoreDrill.enabled`, Sun 04:47) restores one real file
end-to-end (read → decrypt → decompress → hash-verify → write) and asserts it's non-empty. Set
`restoreDrill.canaryPath` to a small, always-present file to keep the restore light and
deterministic; left empty, the drill auto-selects the first non-empty file in the latest
snapshot. Run it on demand with:

```bash
kubectl create job --from=cronjob/dropbox-backup-restore-drill drill-test -n dropbox-backup
kubectl logs -n dropbox-backup job/drill-test          # shows the canary restored & verified
```

This is *automated* verification. It does not replace an occasional **manual** full-restore
spot-check — the `DropboxBackupManualDrillReminder` alert below is a deliberate monthly nudge to
do exactly that by hand.

### Alerts

`prometheusrule.yaml` (`alerting.enabled`) defines the rules below. **Every alert is
`severity: critical` on purpose**: AlertManager forwards only `critical` to Telegram and silently
drops `warning`/`info`, so anything we actually want to see must be `critical`. Each carries a
`namespace: dropbox-backup` label and a `summary` annotation (that's what the Telegram message
renders).

| Alert | Fires when |
|---|---|
| `DropboxBackupStale`              | no fresh snapshot within `alerting.staleAfterSeconds` (26h) — the main "backup stopped producing snapshots" signal; self-clears on the next good snapshot |
| `DropboxBackupCheckFailed`        | `restic check` reported repo corruption (`restic_check_success == 0`) |
| `DropboxBackupExporterDown`       | the exporter is unreachable, so the two metric-based alerts above are blind |
| `DropboxBackupJobFailed`          | a recently-*started* dropbox-backup Job (nightly or drill) failed outright |
| `DropboxRestoreDrillStale`        | no successful restore drill within `alerting.drillStaleAfterSeconds` (8d) — the scariest signal: the repo may not be restorable |
| `DropboxBackupManualDrillReminder`| a calendar reminder (not a failure) on `alerting.manualDrillReminder.{dayOfMonth,hour}` (UTC) to do a manual full-restore spot-check |

### Capacity

Real "nearing capacity" alerting needs galactus-side dataset metrics and is a separate
follow-up (see `/TODO.md`). The `500Gi` on the PV is **advisory only** — NFS PVs don't enforce a
quota and static NFS PVs report no capacity metrics to Kubernetes; the real limit is the
galactus dataset. `restic_size_total` gives a client-side view of repo growth in the meantime.

## Gotchas

Hard-won operational notes from getting this running:

- **Dropbox app scopes + re-authorize.** The `rclone sync` needs a Dropbox app with the right
  scopes (`files.content.read`, `files.metadata.read`, plus `account_info.read`). If you change
  an app's scopes *after* authorizing, you **must re-run the OAuth flow** — the existing
  `refresh_token` keeps the old scopes and syncs fail with permission errors until re-authorized.
  Prefer your own "Scoped access / Full Dropbox" app: Dropbox rate-limits rclone's shared client
  ID hard on large syncs.
- **NFS dirty-page-cache OOM.** The mirror writes large incompressible files to NFS. rclone can
  download faster than the kernel flushes those writes to galactus, and under cgroup v2 the dirty
  page cache counts against the container's memory limit — so an unbounded sync OOM-kills the pod
  even though little is truly "in use". `rclone.bwlimit` caps the download so writeback keeps
  pace, and the container `memory` limit (16Gi) sits above the kernel's dirty-ratio throttle
  point, so the writer is throttled before it can OOM. Tune both together if you change either.

## Data durability

The backup data lives on galactus and survives deletion of the Kubernetes PV/PVC (the NFS
backend is not touched by a PV delete). ArgoCD pruning the app removes the k8s objects, not the
files on the NAS.
