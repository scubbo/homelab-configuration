# Media Quality Profiles

## Philosophy

The homelab Jellyfin setup uses a Quadro P1000 GPU for transcoding. This is a modest workstation
card (4GB VRAM) — it can handle one 4K transcode at a time, but barely. Additionally, most clients
used with this setup cannot direct-play 4K HEVC/HDR content, meaning 4K files almost always require
transcoding rather than direct play.

**Decision:** Target 1080p across the board. 1080p files direct-play on virtually all clients with
no GPU involvement, and the quality difference is imperceptible at typical viewing distances.

## Radarr Quality Profile

**Active profile:** `HD-1080p` (id=4)

All movies should use this profile. Allowed qualities (in ascending preference order):

| Quality | Notes |
|---------|-------|
| HDTV-1080p | Acceptable but lowest preference |
| WEBDL-1080p | Good |
| WEBRip-1080p | Good |
| Bluray-1080p | **Best allowed** — encode source, visually near-transparent at ~5-15 GB |

`Remux-1080p` is **not allowed** (see below) — lossless, but ~3x the size for no perceptible 1080p gain.

**Cutoff:** Bluray-1080p — Radarr stops searching for upgrades once this quality is reached.

**Upgrades allowed:** No — once a file meets the cutoff, don't replace it.

### Why Remux-1080p is not allowed

Remux-1080p is a lossless Blu-ray rip (MKV). At 1080p it direct-plays fine, but files run
25-42 GB — roughly 3x a Bluray-1080p encode (~5-15 GB) that is visually near-transparent at
normal viewing distances. Across a large library the storage and download-time cost outweighs
the imperceptible 1080p quality gain, so it is excluded.

Remux-2160p is 4K HDR content — same client-compatibility/transcoding problem as BR-DISK.
Avoid.

### Why BR-DISK is not allowed

BR-DISK files are raw Blu-ray disc images (`.iso`). They require the `bluray:` FFmpeg protocol,
carry very high bitrates (~60 Mbps), and are almost never direct-playable. They will always
transcode, and that transcode is slow even with GPU acceleration.

## Adding New Movies

When adding a movie in Radarr, always select the **HD-1080p** quality profile. The UI remembers
the last-used profile, so if the previous add used a different profile, change it manually.

## Sonarr

TV shows have not been reviewed under this policy yet. Check and align Sonarr profiles when
time permits.
