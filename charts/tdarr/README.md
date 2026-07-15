# Tdarr — keep the movie library browser-Direct-Play (H.264 MP4)

Non-technical users play movies in a **web browser** via Jellyfin. For a movie to start
**instantly with no server-side transcode**, the *stored file* must be all of:

| Requirement | Why |
|---|---|
| **H.264** video | Browsers can't reliably decode HEVC/AV1 → spin. |
| **AAC** audio | Browsers can't decode DTS/TrueHD/(often)AC3 → forces an audio transcode. |
| **MP4** container | **Browsers can't Direct Play MKV** — they need it remuxed. MP4 plays natively. |
| **`+faststart`** | Moves the `moov` atom to the front so playback starts without downloading the whole file. |
| **≲ 12 Mbps** | A 25–40 Mbps Blu-ray remux is too fat to stream and buffers even as clean MP4. |

Miss *any* one and the browser spins. Tdarr watches the library and normalises every movie to
that shape, replacing the file in place. End state: instant browser Direct Play, zero runtime
transcode. Reachable at `http://tdarr.avril`.

## The plugin (baked into this chart)

`charts/tdarr/plugins/Tdarr_Plugin_scubbo_hevc_to_h264.js` is shipped as a **ConfigMap** and an
**init-container** copies it into Tdarr's `Local` plugins dir on every start (so it survives a
config-PVC rebuild and stays in sync with git). Its logic:

- **HEVC** (8 *or* 10-bit) or **over-cap H264** → transcode to H.264 MP4, GPU-decoded, 10-bit
  downconverted inside CUDA (`scale_cuda=format=yuv420p`), capped at **12 Mbps**, `+faststart`.
- **Under-cap H264 in a non-MP4 container** → fast **remux** to MP4 (no re-encode).
- **Under-cap H264 already in MP4** → skip.
- Audio: copy if already AAC, else re-encode to AAC. Subtitles: **dropped** (MP4 can't hold ASS/PGS,
  and extracting many tracks at play-time is itself a slow-start cause).
- AV1 / mpeg4 → **left untouched** (browsers handle AV1; mpeg4 is rare).

> The 10-bit `scale_cuda` step is essential: the P1000's `h264_nvenc` is 8-bit only, and most of
> the library's HEVC is 10-bit. Without it every 10-bit transcode fails with
> *"Impossible to convert between the formats … h264_nvenc"*.

## What the chart wires up

- **GPU**: `runtimeClassName: nvidia`, `nvidia.com/gpu: 1`, `NVIDIA_VISIBLE_DEVICES=all` /
  `NVIDIA_DRIVER_CAPABILITIES=all` — the same P1000 (node `epsilon`) Jellyfin uses.
- **Media**: the shared TrueNAS NFS export (`galactus.avril:/mnt/low-resiliency-with-read-cache/ombi-data/`)
  mounted **RW** at `/data` → library at `/data/media/movies`. Same export Jellyfin/arr write to as
  UID/GID 1000, so **no new NFS-server setup**.
- **Config**: iSCSI (`freenas-iscsi-csi`) PVC holding `/app/server`, `/app/configs`, `/app/logs`.
- **Transcode scratch**: `emptyDir` at `/temp` (node-local, keeps heavy I/O off the media NFS).
- **Local plugin**: ConfigMap `…-local-plugins` + `install-local-plugins` init-container.

## Prerequisite: GPU time-slicing

The P1000 is otherwise held exclusively by Jellyfin. `app-of-apps/nvidia-device-plugin.jsonnet`
advertises it as **2** slots via the device-plugin's config-file ConfigMap
(`config.map.default → sharing.timeSlicing.replicas: 2`) so Tdarr can co-schedule. Time-based
sharing only — no VRAM isolation on the 4 GB card; runtime contention is managed by the schedule
(below). Confirm after deploy:

```bash
kubectl describe node epsilon | grep nvidia.com/gpu   # Capacity/Allocatable should show 2
kubectl -n jellyfin get pods                            # Jellyfin still Running
kubectl -n tdarr get pods                               # tdarr Running, not Pending
```

## Post-deploy configuration (Tdarr UI, one-time)

Libraries/plugins/schedule/workers live in Tdarr's DB, not files — configure once at
`http://tdarr.avril`.

1. **Library** → add **Source** `/data/media/movies`, transcode cache `/temp`, Process Library **ON**.
2. **Transcode Options** → add the Local plugin (paste ID, type **Local**):
   `Tdarr_Plugin_scubbo_hevc_to_h264`. This one plugin does everything above — no Migz/Smoove/Flow
   needed. (If it doesn't resolve, hit **Sync node plugins** on the Flows page.)
3. **Filters** → **Resolutions to skip**: `4KUHD`. 4K Dolby-Vision files error on transcode *and*
   won't browser-play anyway — handle them by re-grabbing 1080p (see stragglers).
4. **Staging** → tick **Auto accept successful transcodes** (else finished transcodes never
   replace the source).
5. **Workers** (node panel):
   - **Transcode GPU = 1** — does the HEVC/over-bitrate encodes.
   - **Transcode CPU = 1** — does the remuxes. A remux is `-c:v copy` = a *CPU* task; without a CPU
     worker those files sit forever at **"Require CPU Worker."**
6. **Schedule** (node/library) → enable only overnight hours so Tdarr doesn't fight Jellyfin/downloads
   for GPU + NFS. ⚠️ **The scheduler runs on UTC** — offset from `America/Los_Angeles` accordingly
   and *watch when workers actually start*.

## Confirming correct operation

1. **On disk** — a processed file should be `.mp4`, `h264`, `aac`, ≲12 Mbps, faststart:
   ```bash
   POD=$(kubectl -n tdarr get pod -l app.kubernetes.io/name=tdarr -o name)
   F="/data/media/movies/<Movie>/<file>.mp4"
   kubectl -n tdarr exec $POD -- ffprobe -v error -show_entries stream=codec_type,codec_name \
     -of csv=p=0 "$F"                                  # expect: h264/video, aac/audio
   kubectl -n tdarr exec $POD -- ffprobe -v error -show_entries format=bit_rate \
     -of default=nk=1:nw=1 "$F"                        # expect: < ~13000000
   ```
2. **Jellyfin** — play in a browser: **Dashboard → Playback** should show **Direct Play**, and it
   should start in a couple of seconds (no ffmpeg spawned in the jellyfin pod).

## Notes / gotchas (hard-won)

- **The spin had four stacked causes**: HEVC codec, MKV container, missing faststart, and (for
  remuxes) excessive bitrate. Fixing only the codec is not enough.
- **No VRAM isolation** from time-slicing — the overnight schedule is what keeps Tdarr and a live
  Jellyfin transcode off the 4 GB card at once.
- **Shared NFS**: library + downloads + transcode-read all hit one export. A big download backlog
  (SAB) will crawl the remux queue — pause SAB or schedule off-hours.
- **Stragglers not handled by the plugin**: AV1 (left as-is — browsers play it); mpeg4/AVI (rare);
  4K UHD / Blu-ray-disc (ISO) rips (skipped — re-grab as 1080p via Radarr, which is blocked from
  disc releases by a "Must Not Contain" release profile).
- **Subtitles are dropped.** If you want them back, convert text tracks to `mov_text` on the MP4
  (image/PGS subs can't go in MP4); do it selectively to avoid the play-time extraction stall.
