# Tdarr — keep the movie library browser-playable (H.264)

Tdarr watches the movie library and transcodes any video that is **not H.264/AVC** into
H.264 (via the P1000's NVENC), replacing the file in place. The end state: every stored movie
Direct-Plays in a web browser through Jellyfin, with **zero runtime transcoding**. See
`docs/todo/tdarr-pre-transcode-deployment.md` for the full rationale and the decisions behind
this deployment.

This chart deploys a single pod running the Tdarr **server + an internal transcode node**
(`internalNode=true`). It is reachable at `http://tdarr.avril`.

## What the chart wires up

- **GPU**: `runtimeClassName: nvidia`, `nvidia.com/gpu: 1`, and `NVIDIA_VISIBLE_DEVICES=all` /
  `NVIDIA_DRIVER_CAPABILITIES=all` — the same P1000 (node `epsilon`) Jellyfin uses.
- **Media**: the shared TrueNAS NFS export (`galactus.avril:/mnt/low-resiliency-with-read-cache/ombi-data/`)
  mounted **read-write** at `/data`, so the movie library is at `/data/media/movies` — the exact
  path Radarr uses. This is the same export Jellyfin and the arr-stack already write to as
  UID/GID 1000, so **no new NFS-server setup is required**.
- **Config**: an iSCSI (`freenas-iscsi-csi`) PVC holding `/app/server`, `/app/configs`, `/app/logs`.
- **Transcode scratch**: an `emptyDir` at `/temp` — node-local disk on epsilon, so the heavy
  source-read + output-write does **not** thrash the shared media NFS.

## Prerequisite: GPU time-slicing (in this same change)

The P1000 is reserved *exclusively* by Jellyfin. For Tdarr's pod to even schedule onto the GPU,
`app-of-apps/nvidia-device-plugin.jsonnet` advertises the card as **2** slots
(`sharing.timeSlicing.replicas: 2`). This is *time-based* sharing with **no VRAM isolation** on
the 4 GB card, so runtime collisions are instead avoided by Tdarr's **off-hours schedule** and a
**1-worker GPU cap** (configured below), not by Kubernetes.

After deploy, confirm both are true:

```bash
kubectl describe node epsilon | grep nvidia.com/gpu   # Capacity/Allocatable should show 2
kubectl -n jellyfin get pods                            # Jellyfin still Running (unchanged)
kubectl -n tdarr get pods                               # tdarr pod Running, not Pending
```

If the Tdarr pod is stuck `Pending` with `Insufficient nvidia.com/gpu`, the device-plugin
DaemonSet on epsilon has not picked up the time-slicing config yet.

## Post-deploy configuration (Tdarr UI)

Tdarr stores libraries, plugins and schedules in its own DB, not in files — so these are one-time
UI steps after the pod is up. Open `http://tdarr.avril`.

### 1. Add the movie library

- **Libraries → + → Add** with **Source** = `/data/media/movies`.
- **Transcode cache**: `/temp`.
- Leave **Process Library = ON**.

### 2. Transcode settings — non-H.264 → H.264, tone-map HDR, convert lossless audio

The three decisions this implements (per the plan):

| Concern | Decision |
|---|---|
| Video | Only touch files whose video codec **≠ H.264**; encode `h264_nvenc` (~CQ 21-23 / ~8-12 Mbps 1080p). Skip files already H.264 (no generation loss). |
| HDR | **Tone-map HDR → SDR** (browser-first). Without tone-mapping, colors wash out. |
| Audio | Convert **lossless** (TrueHD / DTS-HD MA) → **AC3 5.1**; leave already-compatible AAC/AC3 as-is. |

Tone-mapping and conditional audio are cleanest with a **Tdarr Flow** (the node-based pipeline):
a video node set to `h264_nvenc` with an HDR-tone-map step, plus an audio node that transcodes
only non-AC3/AAC tracks to AC3. The classic-plugin route (e.g. the "Migz Transcode Using Nvidia
GPU" + a Migz audio plugin) covers the video/audio codec swap but tone-mapping needs a Flow node
or a community tone-map plugin. **Verify the exact node/plugin names against the running Tdarr
version's plugin library** — Tdarr's plugin catalog changes between releases.

Container stays **MKV** — Jellyfin remuxes MKV→fMP4 for browsers with no transcode.

### 3. Off-hours schedule + 1-worker GPU cap

- On the **node** (and/or the library) open the **Schedule** grid and enable **only** your
  overnight hours (e.g. ~1am–8am), leaving daytime hours disabled.
- ⚠️ **Timezone gotcha**: Tdarr's scheduler has historically run on **UTC, not local time**. We
  are `America/Los_Angeles` (UTC-7/-8), so offset the enabled cells accordingly — e.g. local 1am
  ≈ UTC 08:00/09:00. **Watch when workers actually start** and adjust; newer versions may respect
  local time, so verify rather than assume.
- Set the **GPU/transcode worker limit to 1** so at most one transcode ever touches the P1000.
- Workers finish their current file before the schedule pauses them (they don't kill mid-file).

### 4. Scope: normalize the whole library

Let Tdarr scan and process the **entire existing library** (not just new grabs). It will work
through the backlog over successive overnight windows. Expect this to take a while — it's a
single 4 GB GPU limited to off-hours with 1 worker, over a shared NFS export.

## Escape hatch — force-transcode one movie now

To push a freshly-grabbed movie through immediately, outside the overnight window:

1. In the UI **search bar**, find the file and **move it to the top of the queue** (new scans are
   auto-prioritized to the top anyway).
2. Ensure **Process Library = ON**.
3. Manually **bump the transcode worker limit** on the node (the worker-limit buttons override the
   idle schedule) — use a **transcode** worker, not a general worker (general workers clear health
   checks first).
4. Drop the worker limit back to 0 (or let the schedule take over) when it's done.

> A file that already meets requirements (already H.264) is marked **Not required** and skipped —
> there is no native "force re-encode an already-compliant file" button.

## Confirming correct operation

Three independent signals that it's actually working:

1. **Tdarr UI** (`http://tdarr.avril`) — the library card shows a rising **Transcoded** count and
   per-file status **Transcode success**; the **Transcodes** tab lists each completed file with its
   before/after codec and space saved. A file already H.264 shows **Not required** (correct — it was
   skipped, not failed).

2. **Codec on disk** — spot-check a processed file with `ffprobe` (bundled in the Tdarr image; the
   media is at `/data` inside the pod). Adjust the binary path if `ffprobe` isn't on `PATH` for your
   image version:
   ```bash
   POD=$(kubectl -n tdarr get pod -l app.kubernetes.io/name=tdarr -o name)
   # Video codec -> expect: h264
   kubectl -n tdarr exec $POD -- ffprobe -v error -select_streams v:0 \
     -show_entries stream=codec_name -of default=nk=1:nw=1 "/data/media/movies/<Movie>/<file>.mkv"
   # Audio codec(s) -> expect: aac / ac3 (no truehd / dts-hd)
   kubectl -n tdarr exec $POD -- ffprobe -v error -select_streams a \
     -show_entries stream=codec_name -of default=nk=1:nw=1 "/data/media/movies/<Movie>/<file>.mkv"
   ```

3. **Jellyfin play method** — the real acceptance test. Play the movie in **Chrome**, then in
   Jellyfin **Dashboard → Playback (active devices)** the stream's **Play method** should read
   **Direct Play** (not "Transcode" / "Direct Stream"). Direct Play = success.

Also confirm Radarr did not re-import-loop: the movie still shows once, with its file present (no
duplicate and no flip to "missing"), after Tdarr replaced the file.

## Acceptance criteria

1. An existing x265 library file is auto-transcoded to H.264 and replaced in place; Radarr still
   tracks the movie (same path/filename → no re-import loop).
2. A newly-grabbed x265 fallback is normalized to H.264 within a reasonable window.
3. Jellyfin plays the result in **Chrome** as **Direct Play** (no runtime transcode).
4. Tdarr transcoding never starves a live Jellyfin playback (off-hours schedule + 1-worker cap).

## Notes / gotchas

- **No VRAM isolation**: time-slicing shares GPU *time*, not the 4 GB of VRAM. The off-hours
  schedule is what actually keeps Tdarr and a live Jellyfin transcode off the card simultaneously.
- **Shared NFS**: download/unpack/library/transcode-read all share one export; SAB unpack already
  saturates it. Off-hours scheduling doubles as I/O-contention avoidance.
- **Radarr**: `upgradeAllowed=false`, so Tdarr's in-place file change does not trigger a
  re-download; keep the same path + filename.
