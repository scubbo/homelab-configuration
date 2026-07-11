# Sonarr "stuck, not downloading" — actually import-blocked (2026-07-10)

## Symptoms
- Sonarr appeared "stuck" — nothing new arriving in the library.
- Reported as "not downloading anything."

## Actual problem
Sonarr was **not** stuck downloading — it was stuck **importing**. Downloads completed in
SABnzbd but piled up in the queue in `importBlocked` state, so nothing reached
`/data/media/tv`. From the outside this looks identical to "not downloading."

Queue at time of investigation: **32 items** — 27 `importBlocked` (all *Community*), 5 in a
separate stale `importing` limbo.

## Investigation was blocked by expired local credentials
Both normal read paths were dead:
- **kubectl** — k3s client cert in `~/.kube/config` **expired 2025-07-03** (`notAfter=Jul 3
  04:36:34 2026 GMT`; subject `O=system:masters, CN=system:admin`). Cert lifetime is 1 year,
  so this recurs annually around early July.
- **argocd** — session token expired (`token is expired`).
- SSH to `epsilon` works as `scubbo`, but `/etc/rancher/k3s/k3s.yaml` is root-only and sudo
  needs a password → could not self-renew.
- The NFS boxes (`rasnu2.avril`, `rassigma.avril`) don't accept SSH from the laptop.

**Workaround: diagnose and fix entirely through Sonarr's HTTP API** (see runbook below). The
expired cert is a laptop-credential problem and has zero effect on the in-cluster apps.

## Root cause of the 27 blocked imports
Every blocked item had the identical status message:

> Found matching series via grab history, but release was matched to series by ID.
> Automatic import is not possible. See the FAQ for details.

All 27 were *Community* releases from `LeagueNF` carrying Netflix per-season year tokens
(`Community.2014.S05…`, `Community.2015.S06…`, `Community.2010.S02…`). Community's TVDB year
is **2009**, so at import time Sonarr can't re-derive the series from the release name by
title+year. It falls back to grab history, sees the grab was matched **by series ID** (the
signature of an *interactive/manual search* grab), and refuses to auto-import as a safety
measure (so it can't file episodes under the wrong show).

Manual-import candidates for all 27 resolved cleanly to `Community` with correct S/E and
**zero rejections** — confirming the block was purely the "matched by ID" safety gate, not a
real parsing/quality problem.

## Ruled out
- **Disk** — `/config` 232 MB free (tight but not full); root folder `/data/media/tv`
  accessible with ~7.4 TB free.
- **Download client** — only SABnzbd configured, enabled, completing downloads fine.
- **Indexers / Sonarr health** — no client or indexer warnings (only a benign
  "update available").
- **Grab pipeline** — Jujutsu Kaisen imported normally two days prior, so the path works for
  cleanly-parseable releases.

## Secondary finding: 5 stale `importing` entries (older, unrelated)
Five non-Community items had been stuck in `importing` since **Mar–May 2026**. Their
manual-import candidates came back **empty** → the completed download folders were gone
(likely SABnzbd completed-download cleanup while Sonarr still held them queued). These are
orphaned queue entries; a rescan cannot help (no files exist).
- 1 (`Rick and Morty S09E01`) already had `hasFile=true` → pure stale cruft.
- 4 (`Invincible S04E06`, `Shrinking S03E09`, `Shrinking S03E11`, `One Piece E025`) were
  genuinely missing → needed a fresh grab.

## Resolution
All actions done via the Sonarr API (`https://sonarr.avril/api/v3`, header
`X-Api-Key: <key>`; API key from Sonarr → Settings → General).

1. **Cleared the 27 Community blocks** with a per-download `ManualImport` command
   (`importMode: auto` → hardlink/copy, source untouched, fully reversible). Queue 32 → 5,
   blocked → 0. Episodes filed into `Community (2009)`.
2. **Removed the 5 stragglers**:
   - Rick & Morty: plain remove (`blocklist=false&skipRedownload=true`) — already in library.
   - The 4 missing: remove `+ blocklist=true&skipRedownload=false` → Sonarr auto-searched and
     re-grabbed fresh releases within seconds; they downloaded and imported normally.

Final state: queue healthy, 0 blocked, 0 stuck, fresh grabs downloading.

## Runbook: diagnose Sonarr without kubectl
Set the key once, then all calls are read-only `GET`s:

```bash
export SK="<sonarr-api-key>"; B="https://sonarr.avril/api/v3"   # -k: internal .avril cert

# Is Sonarr even up? (no key needed)
curl -sSk -o /dev/null -w '%{http_code}\n' https://sonarr.avril/ping   # 200 = up

# Health, disk, root folders
curl -sSk -H "X-Api-Key: $SK" "$B/health"     | jq '.'
curl -sSk -H "X-Api-Key: $SK" "$B/diskspace"  | jq '.[] | {path, freeMB:(.freeSpace/1e6|floor)}'
curl -sSk -H "X-Api-Key: $SK" "$B/rootfolder" | jq '.[] | {path, accessible}'

# The key view: queue states + block reasons
curl -sSk -H "X-Api-Key: $SK" "$B/queue?pageSize=50&includeUnknownSeriesItems=true" \
  | jq '{total:.totalRecords, states:([.records[].trackedDownloadState]|group_by(.)|map({(.[0]):length})|add)}'
curl -sSk -H "X-Api-Key: $SK" "$B/queue?pageSize=50&includeUnknownSeriesItems=true" \
  | jq -r '.records[] | select(.statusMessages|length>0) | "\(.title): \(.statusMessages|map(.messages|join("; "))|join(" || "))"'

# What Sonarr proposes to import for a blocked download (URL-encode the id!)
curl -sSk -H "X-Api-Key: $SK" --get "$B/manualimport" \
  --data-urlencode "downloadId=<SABnzbd_nzo_xxx>" --data-urlencode "filterExistingFiles=false" \
  | jq '.[] | {series:.series.title, s:.seasonNumber, e:(.episodes|map(.episodeNumber)), rej:(.rejections|map(.reason))}'
```

Gotchas learned the hard way:
- `status` is a **read-only variable in zsh** — name loop vars `st`, not `status`.
- URL-encode `downloadId` via `curl --get --data-urlencode`; a raw `?downloadId=…&…` can trip
  "URL rejected: Malformed input to a URL function".

### Clearing an `importBlocked` item ("matched by ID") — WRITE
Verify candidates have **0 rejections** first, then per download:
```bash
payload=$(curl -sSk -H "X-Api-Key: $SK" --get "$B/manualimport" \
    --data-urlencode "downloadId=$id" --data-urlencode "filterExistingFiles=false" \
  | jq --arg dlid "$id" '{name:"ManualImport", importMode:"auto", files:[ .[] | {
      path, seriesId:.series.id, episodeIds:[.episodes[].id],
      quality, languages, releaseGroup, downloadId:$dlid, indexerFlags:(.indexerFlags // 0) } ]}')
curl -sSk -H "X-Api-Key: $SK" -H "Content-Type: application/json" -X POST "$B/command" -d "$payload"
```

### Clearing a stale `importing` entry (empty candidates) — WRITE
Use the queue **record id** (`.id`, not `.downloadId`):
```bash
# already in library → plain remove:
curl -sSk -H "X-Api-Key: $SK" -X DELETE "$B/queue/<id>?removeFromClient=true&blocklist=false&skipRedownload=true"
# missing → remove + blocklist + auto re-search:
curl -sSk -H "X-Api-Key: $SK" -X DELETE "$B/queue/<id>?removeFromClient=true&blocklist=true&skipRedownload=false"
```

## Follow-ups
1. **Renew laptop cluster creds** (recurs ~annually, early July): rotate the k3s client cert on
   `epsilon` and copy the fresh `/etc/rancher/k3s/k3s.yaml` to `~/.kube/config` (fixing the
   `server:` from `127.0.0.1` to `epsilon`). Re-login argocd. Requires Jack's sudo.
2. **Recurrence:** the "matched by ID" block returns for any interactive-search grab whose
   release name doesn't cleanly parse (year-mismatch shows are the classic trigger). No
   permanent fix — a one-time manual import clears it.
