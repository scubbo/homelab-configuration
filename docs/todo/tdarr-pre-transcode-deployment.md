# Tdarr pre-transcode — keep the media library browser-playable (H.264)

**Status: PLANNED / hand-off spec.** Not implemented. Written for an implementing agent
with no prior context. Read the repo `CLAUDE.md` first (app-of-apps GitOps, read-only
kubectl/argocd, commit+PR only, don't skip hooks).

## Problem & goal
Non-technical users play movies in a **web browser (Chrome)** via Jellyfin. Browsers can't
reliably play **HEVC/x265** — Jellyfin attempts Direct Play and the player just spins. The
fix must be **transparent + automatic**: any browser, no client/app/settings changes.

Chosen design — **pre-transcode on fetch, not at runtime**:
1. Radarr prefers an out-of-the-box-playable release (**x264/H.264**) — already configured.
2. When only x265/HEVC (or other non-H.264) is available, grab it, then **transcode to
   H.264 on disk** so the *stored* file is always browser-direct-playable.

Tool: **Tdarr** (`ghcr.io/haveagitgat/tdarr`) — a library-watching transcode automator
(server + node). Lighter alternative: **Unmanic**. It scans the library, transcodes any
non-H.264 video → H.264 via the P1000 (NVENC), replaces the file in place, and auto-picks
up new grabs. End state: library video is always H.264 → Jellyfin direct-plays (remuxes
MKV→fMP4, no transcode) in any browser; zero runtime transcode; every movie stays present.

## Current environment (verified facts)
- **Cluster**: k3s, app-of-apps GitOps. Add an app via `app-of-apps/<name>.jsonnet`; local
  charts under `charts/<name>` (see `app-of-apps/app-definitions.libsonnet`).
- **GPU**: one Nvidia Quadro **P1000 (Pascal, 4 GB VRAM)** on node `epsilon`. Driver
  535.216.01 / CUDA 12.2. NVDEC (incl. HEVC 10-bit) + NVENC (h264/hevc). HW transcode is
  confirmed working.
- **Jellyfin**: ns `jellyfin`, `charts/jellyfin`. Requests `nvidia.com/gpu: 1`
  **exclusively**, `runtimeClassName: nvidia`. `AllowHevcEncoding=false` (its transcodes
  output H.264).
- **nvidia-device-plugin**: deployed via `app-of-apps/`, runs in `kube-system`. Currently
  advertises `nvidia.com/gpu: 1` on epsilon — **no time-slicing** (so only one pod can hold
  the GPU today).
- **Radarr** (`arr-stack` ns, `charts/arr-stack`): profile `HD-1080p` (id 4) — Remux-1080p
  excluded; Custom Format `HEVC (x265)` = **-50**, `minFormatScore = -100` → x264 preferred,
  x265 allowed as fallback. So Radarr grabs x264 when it exists; Tdarr normalizes the x265
  fallbacks. **Do not change this to hard-reject** — that leaves only-x265 titles unmet
  (already learned the hard way).
- **Movie library path**: Radarr root folder is **`/data/media/movies`**.
- **Storage caveat**: the arr-stack pods mount media over NFS. `charts/arr-stack/values.yaml`
  names `dataNFSServer: rasnu2.avril:/mnt/NEW_BERTHA/ombi-data`, but the running SAB pod's
  `/data/usenet` was actually `galactus.avril:/mnt/low-resiliency-with-read-cache/ombi-data`.
  **CONFIRM the real NFS backing of `/data/media`** before wiring Tdarr's mounts. Everything
  (download/unpack/library) shares one NFS export → I/O contention is real (SAB unpack
  already saturates it), which matters for Tdarr's transcode scratch (see below).

## Design decisions (⚠ = needs Jack's sign-off)

### ⚠ GPU sharing — the key issue
P1000 is exclusively Jellyfin's; Tdarr's node also needs it. Options:
- **A) Time-slicing** — configure nvidia-device-plugin (`sharing.timeSlicing.resources:
  [{name: nvidia.com/gpu, replicas: 2}]`) so epsilon advertises `nvidia.com/gpu: 2` and both
  Jellyfin + Tdarr can schedule. Caveat: **no VRAM isolation** — 4 GB card, so a Tdarr
  transcode + a live Jellyfin transcode simultaneously may exhaust VRAM (one fails/retries).
- **B) Off-hours scheduling** — Tdarr transcodes only when Jellyfin is idle (Tdarr scheduler).
  Safer for a 4 GB card; slower to clear the backlog.
- **C) CPU transcode** — no GPU contention, but slow.
- **Recommendation**: **A**, limiting Tdarr to **1 concurrent GPU transcode** and low/off-peak
  priority — collisions are rare because once the library is H.264, Jellyfin mostly
  direct-plays (little runtime transcoding). **Jack to decide A vs B.**

### ⚠ HDR titles
HDR content is inherently x265/10-bit. Browser-safe = transcode **HDR→SDR with tone-mapping**
(a real quality tradeoff — without tone-mapping, colors wash out). **Decide**: tone-map
HDR→SDR (default, browser-first) vs exempt HDR titles (keep as-is, accept native-client-only).
After the recent 4K→1080p downgrade, HDR should be rare.

### ⚠ Audio
Keep browser-compatible audio (AAC/AC3) as-is; **decide** whether to transcode lossless
(TrueHD/DTS-HD MA) → AC3/AAC. Keeping lossless can still force an *audio-only* transcode at
play; converting makes files fully direct-play. Recommend converting to AC3/AAC 5.1.

### Transcode flow (Tdarr)
- **Only touch files whose video codec ≠ H.264/AVC** (skip already-H.264 — no needless
  re-encode / generation loss).
- Decode via NVDEC, encode `h264_nvenc`, ~CQ 21-23 (or ~8-12 Mbps 1080p).
- Container: **MKV is fine** (Jellyfin remuxes MKV→fMP4 for browsers with no transcode).
- **Replace in place**, same folder + filename, so Radarr keeps tracking it.
- **Transcode scratch/temp on FAST LOCAL disk** on epsilon if available (a local-path PVC /
  hostPath), NOT the media NFS — transcoding reads the big source + writes the big output;
  doing that on the shared NFS will thrash it. If no local disk, use NFS + schedule off-peak.

### Radarr interaction
Tdarr's in-place replace changes file size/codec; Radarr sees the changed file on its next
scan (fine; `upgradeAllowed=false` → no re-download). Keep the same path/filename so Radarr
doesn't lose track or re-import-loop.

## Deployment outline
- `app-of-apps/tdarr.jsonnet` + `charts/tdarr/` (or a community Helm chart).
- Tdarr **server** + **node** (single pod w/ internal node is fine to start).
- Node: `runtimeClassName: nvidia`, `resources.limits: {nvidia.com/gpu: 1}` (works once
  time-slicing advertises ≥2), `NVIDIA_VISIBLE_DEVICES=all`,
  `NVIDIA_DRIVER_CAPABILITIES=all`.
- Volumes: config PVC (server DB/config); media = the arr-stack media NFS **RW** (mount at
  e.g. `/media`, must reach `/data/media/movies`); transcode cache = local disk if possible.
- Ingress: `tdarr.avril` (Traefik; external-dns auto-registers the `.avril` host).
- nvidia-device-plugin change (option A): update its `app-of-apps` app's Helm values for
  time-slicing; verify epsilon then shows `nvidia.com/gpu: 2` **and Jellyfin still runs**.
- Post-deploy Tdarr config (UI or seeded config): add the movie library
  (`/data/media/movies`), and a transcode plugin/flow "video not h264 → h264 nvenc" (e.g.
  the "Migz Transcode Using Nvidia GPU" classic plugin, or a Flow). Set the scheduler if
  option B; cap concurrent GPU transcodes at 1.

## Acceptance criteria
1. An existing x265 library file is auto-transcoded to H.264 and replaced in place; Radarr
   still tracks the movie.
2. A newly-grabbed x265 (Radarr fallback) is normalized to H.264 within a reasonable window.
3. Jellyfin plays the result in **Chrome** as **Direct Play** (no runtime transcode).
4. Tdarr transcoding never breaks/starves a live Jellyfin playback (GPU sharing verified).
5. No Radarr re-import loop from Tdarr's file changes.

## Open decisions for Jack (resolve before/at implementation)
1. GPU sharing: **time-slicing (A)** vs **off-hours scheduling (B)**.
2. HDR: **tone-map to SDR** (default) vs **exempt HDR** titles.
3. Audio: convert lossless → AC3/AAC (recommended) vs keep.
4. Scope: normalize the **whole existing library** to H.264 (recommended — browser-safety
   everywhere) vs only non-H.264 from now on.

## Related context in-repo
- `docs/media-quality-profiles.md` — quality/codec policy (1080p, x264-preferred, no 4K/Remux).
- `agentic-investigations/2026-07-12-gluetun-vpn-throughput-collapse.md` — unrelated, but the
  same "single NFS export saturates under heavy I/O" lesson applies to Tdarr's scratch dir.
