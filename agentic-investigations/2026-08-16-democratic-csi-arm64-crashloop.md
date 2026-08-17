# democratic-csi node pods crashlooping on rasnu1 (arm64 exec format error)

**Date:** 2026-08-16
**Status:** Root cause identified; fix pending (helm upgrade to be run by Jack)

## Symptom

`homelab-health` dashboard showed 15 firing alerts. 8 of them traced to the
`democratic-csi` namespace:

- 6× `KubePodCrashLooping` (3 each for the two affected pods)
- 2× `KubeDaemonSetRolloutStuck`

Affected pods, both on node **rasnu1**, crashlooping for ~7.5 months:

| Pod | Restarts | Age |
|---|---|---|
| `zfs-iscsi-democratic-csi-node-xj8fl` | ~151,700 | 228d |
| `zfs-nfs-democratic-csi-node-lwjsc` | ~154,500 | 234d |

In each pod the `csi-driver` and `csi-proxy` containers fail; `csi-driver` dies
instantly with:

```
exec bin/democratic-csi: exec format error
```

## Root cause

- **rasnu1 is arm64** (Raspberry Pi, Debian 12). epsilon and culex are amd64.
- The `zfs-iscsi` and `zfs-nfs` Helm releases (chart `democratic-csi-0.14.7`,
  Helm-managed outside GitOps — see `docs/PREREQUISITES.md`) pin the driver
  image by digest:
  `docker.io/democraticcsi/democratic-csi@sha256:7fffba3553a0613c9b2c709588d5658cdc80b0126c9157318224228d8a5f7d35`
- That digest was captured in December 2025 to lock in the `next` tag's
  TrueNAS 13 fixes — but it is the **amd64 platform manifest**
  (`application/vnd.docker.distribution.manifest.v2+json`), not the multi-arch
  **manifest list**. Digest pins bypass architecture resolution, so rasnu1
  pulls the amd64 binary and fails to exec it.
- `csi-proxy` (`csi-grpc-proxy:v0.5.6`) crashes on rasnu1 as a knock-on effect.

## Impact

- rasnu1 cannot mount/unmount democratic-csi volumes. Any pod scheduled there
  with an iSCSI/NFS PVC will fail to start.
- Provisioning was unaffected: both controller Deployments run on amd64 nodes.

## Fix

Repin to the `v1.9.5` **manifest-list** digest. v1.9.5 was released 2026-01-07
(one week after the Dec-2025 `next` build that was originally pinned) and is the
first tagged release containing the TrueNAS 13 / NFS API fixes. Verified
multi-arch (linux/amd64 + linux/arm64):

```
docker.io/democraticcsi/democratic-csi:v1.9.5@sha256:fc3b7d7ed3a616714139525075312758e23a5d425ffb539ad12c9bd20fb6001f
```

Applied via `helm upgrade --reuse-values` on both releases (commands in
`docs/PREREQUISITES.md`; releases are not GitOps-managed because values contain
a TrueNAS API key and SSH private key).

Caveat noted at the time: this also moves the working amd64 nodes from the
Dec-2025 `next` build to the v1.9.5 release. Considered low risk given the
one-week gap between them.

## Lessons

- When pinning images by digest on a mixed-architecture cluster, always use the
  manifest-list digest (Docker Hub tag API `.digest` field), never a
  platform-specific one. Verify with `docker manifest inspect` — the mediaType
  must be a manifest list / OCI index.
- `KubePodCrashLooping` on only a subset of a DaemonSet's pods is a strong hint
  of a node-specific problem; check node architecture early when the error is
  `exec format error`.

## Follow-ups

- [ ] Jack to run the two `helm upgrade` commands and confirm 4/4 containers
      ready on both rasnu1 node pods, and alerts clear.
- [ ] Remaining firing alerts not related to democratic-csi (as of this
      investigation): `TargetDown` (vault), `ServiceDown`/
      `ServiceUnhealthyStatusCode` (pl8calcul8), `KubePodCrashLooping`
      (openclaw), `CPUThrottlingHigh` (blackbox-exporter), plus the standing
      `KubeSchedulerDown`/`KubeProxyDown`/`KubeControllerManagerDown`/
      `Watchdog`/`InfoInhibitor` noise. Worth separate investigation.
