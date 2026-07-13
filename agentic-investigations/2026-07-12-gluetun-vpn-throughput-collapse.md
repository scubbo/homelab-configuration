# SABnzbd/Radarr downloads slow — gluetun VPN tunnel throughput collapse (2026-07-12)

**Status: SOLVED.** Root cause: epsilon's default **208 KB socket buffers**
(`net.core.{r,w}mem_max`) + **`cubic`** congestion control crippled WireGuard on the
high-BDP VPN path. Fix: raise `net.core.{r,w}mem_max` to 8 MB + switch to **BBR** with
**`fq`** qdisc, then recreate the gluetun pod. Result: SAB NNTP **0.5 → ~35 MB/s**
(verified: 1365 MB drained in 39 s); tunnel to a CDN 0.5 → **85 MB/s** (1.28 GB in 15 s);
backlog ETA **29-69 days → ~1 day**. Server region (NL vs Canada) was NOT the cause and
can be reverted.

## Symptoms
- Reported first as "Radarr not searching / not downloading new movies."
- Radarr actually searches + grabs fine; releases hand off to SABnzbd normally.
- SABnzbd accepts jobs but downloads crawl: ~2.6 TB queued, SAB ETA tens of days,
  nothing completing. Radarr shows >1 day ETA for most items (correct given the backlog
  at the crawl rate).

## TL;DR of the localization
Same destination, VPN vs not:

| Path | Sustained throughput |
|---|---|
| epsilon → leaseweb mirror, **direct (no VPN)** | **95 MB/s** |
| SAB pod → leaseweb mirror, **through gluetun VPN** | **0.01 MB/s** |

A ~10,000x collapse to the *same server*, purely from routing through the gluetun
sidecar. So the bottleneck is the **gluetun → ProtonVPN tunnel**, nothing upstream or
downstream of it.

## Ruled OUT (with evidence)
- **Radarr / on-add search:** grabs fire within ~10s of add; `MoviesSearch` works.
- **UsenetServer / the usenet account:** irrelevant — the collapse reproduces against a
  neutral CDN (leaseweb) through the VPN, not just NNTP.
- **epsilon uplink / NIC:** 95 MB/s direct; `eno1` is 1 Gbit, `ip -s link` shows 0
  errors / 0 dropped / 0 collisions.
- **Tunnel MTU:** live-tested `tun0` at 1280 / 1320 / 1420 — all equally slow
  (~10-23 KB/s). Not an MTU/fragmentation problem. (`OPENVPN_MSSFIX` from the OpenVPN era
  is moot under WireGuard.)
- **Packet loss:** 0% both through-tunnel (to 8.8.8.8) and epsilon-direct to the Proton
  WG endpoint. RTT ~142 ms to the NL node (homelab is US-West).
- **Pod resource throttle:** no bandwidth annotation, no namespace LimitRange; gluetun
  1m CPU, sabnzbd 55m of a 2000m limit. Cloudflare-to-`/dev/null` (near-zero CPU) also
  throttles → not CPU.
- **Node traffic shaping:** no `tc` qdisc shaping on `eno1`; conntrack 4157/1048576.
- **ProtonVPN the service:** a laptop running the ProtonVPN app sustained ~190→240 Mbps
  to a **Netherlands** server for minutes (test was under intermittent load, but clearly
  >> the tunnel's KB/s). So ProtonVPN NL can be fast; the in-cluster gluetun tunnel is
  the differentiator.

## Leading hypothesis: node socket buffers + congestion control
epsilon's kernel network tuning (read from `/proc/sys`):
```
net.core.rmem_max = 212992   (208 KB — Linux default)
net.core.wmem_max = 212992   (208 KB)
net.ipv4.tcp_congestion_control = cubic
net.core.default_qdisc = fq_codel
```
WireGuard's UDP socket is bounded by `net.core.{r,w}mem_max`. On a high bandwidth-delay
-product path (142 ms to NL, ~25 ms to Canada), a 208 KB buffer is far below the BDP
(NL needs ~7 MB, Canada ~1.25 MB for tens of MB/s), so the initial burst overflows the
buffer → packet loss → `cubic` collapses and recovers slowly. This explains every
observation: burst-then-collapse, server/protocol independence, Canada only marginally
better (lower BDP), ~30 KB/s *per connection* across 20 conns (loss-driven, not mere
windowing), and the laptop being fine (its own OS stack). NOT YET TESTED — this is the
next thing to try.

Why the laptop differs: the ProtonVPN app runs on macOS with its own (larger) buffers and
network stack; gluetun's kernelspace WG on epsilon inherits epsilon's tiny defaults.

**CONFIRMED (2026-07-13).** On epsilon: `sudo modprobe tcp_bbr; sudo sysctl -w
net.core.rmem_max=8388608 net.core.wmem_max=8388608 net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr`, then `kubectl rollout restart
deployment/arr-stack-sabnzbd`. BBR verified active in the pod netns. SAB NNTP jumped to
~35 MB/s sustained; CDN-through-tunnel to 85 MB/s. Root cause + fix proven.

## Measurement trap encountered
Every fresh VPN connection (pod restart / SAB app-restart) **bursts** high for ~60 s then
collapses:

| | OpenVPN | WireGuard |
|---|---|---|
| Fresh-connection burst | ~8 MB/s | ~12 MB/s (726 MB drained in 60 s — real) |
| After ~1 min | ~0.3-0.5 MB/s | ~0.5 MB/s (later readings ~0.01) |

**Do not trust the first ~60 s.** Measure sustained (mbleft drain over a multi-minute
window, or a 40s+ single-stream download to a known-fast server).

## Changes made along the way (config now on `main`)
- **PR #20:** `OPENVPN_MSSFIX=1400` — helped the burst, not sustained. (Dead once on WG.)
- **PR #21:** `VPN_TYPE: openvpn → wireguard`. Faster burst, same sustained collapse.
- **PR #22:** removed `DNS_KEEP_NAMESERVER=on` — closes the gluetun DNS-leak (lookups now
  in-tunnel). Independent hygiene fix; kept.
- **PR #23 (merged):** `SERVER_COUNTRIES: Netherlands → Canada` — connected Vancouver BC
  (~25 ms). Sustained NNTP only ~0.63 MB/s (vs NL ~0.5). **Server region is NOT the fix.**
  Consider reverting to Netherlands (better DMCA posture) once the real fix lands.
- **Secret:** added key `wireguard-private-key` to `gluetun-protonvpn` (namespace
  `arr-stack`) from the `~/Downloads/gluetun-2-*.conf` WireGuard config. ProtonVPN WG
  keys are server-agnostic, so it works for any `SERVER_COUNTRIES`.

Config source of truth: `manifests/gluetun/kyverno-gluetun-inject.yaml` (Kyverno
ClusterPolicy `inject-gluetun-sidecar`), synced by `app-of-apps/gluetun-vpn.jsonnet`.
Only pods labelled `gluetun-vpn: "true"` get the sidecar — currently
`arr-stack-sabnzbd` and `arr-stack-ytdlpaas`. Kyverno injects at **pod creation**, so
policy changes require a `rollout restart` to take effect.

## Side-findings (not the root cause, but bit us)
- **AdGuard Home blocks speedtest domains.** `speed.hetzner.de` will NOT resolve via the
  homelab resolver (192.168.1.1) or CoreDNS, while `google.com` resolves 6/6. This is an
  AdGuard blocklist, not a DNS outage — it wasted time during testing. Use a neutral
  mirror (`mirror.leaseweb.com`) or `speedtest.tele2.net` (resolves) instead. NOTE:
  `speedtest.tele2.net`'s IPv4 endpoint is itself slow (~0.4 MB/s) — a bad yardstick;
  leaseweb gave a true 95 MB/s.
- **kubectl/argocd break while on the VPN.** When Jack's laptop is on ProtonVPN, homelab
  hostnames (`epsilon`) stop resolving, so `kubectl` fails with `lookup epsilon: no such
  host`. Do cluster work off-VPN.

## Diagnostic runbook (the decisive tests)
```bash
SAB=$(kubectl -n arr-stack get pods -o name | grep sabnzbd | sed 's|pod/||')

# 1. THE decisive test: same server, direct vs through-VPN.
# epsilon direct (no VPN):
ssh epsilon 'curl -4 -so /dev/null --max-time 20 -w "%{speed_download} B/s\n" \
  "http://mirror.leaseweb.com/ubuntu-releases/22.04/ubuntu-22.04.5-live-server-amd64.iso"'
# SAB through the VPN (same URL):
kubectl -n arr-stack exec "$SAB" -c sabnzbd -- curl -4 -so /dev/null --max-time 40 \
  -w "%{speed_download} B/s\n" \
  "http://mirror.leaseweb.com/ubuntu-releases/22.04/ubuntu-22.04.5-live-server-amd64.iso"

# 2. Sustained SAB NNTP drain (real rate, ignores burst): sample mbleft over ~60s.
export SAK=<sab-api-key>; H=https://sabnzbd.avril/api
curl -sSk --get "$H" --data-urlencode mode=queue --data-urlencode output=json \
  --data-urlencode apikey=$SAK | jq -r '.queue | {kbpersec, timeleft, mbleft, noofslots}'

# 3. gluetun tunnel: interface/MTU, endpoint, loss.
kubectl -n arr-stack exec "$SAB" -c gluetun -- ip -o link show          # tun0 is the VPN iface
kubectl -n arr-stack logs "$SAB" -c gluetun --tail=40 | grep -iE "Connecting to|Public IP"
kubectl -n arr-stack exec "$SAB" -c sabnzbd -- ping -c 20 -i 0.2 8.8.8.8 # loss/RTT thru tunnel
```

## Remaining finish-line tasks (fix confirmed; make it durable)
1. **Persist the sysctls** — currently runtime-only, lost on reboot. Add to
   `/etc/sysctl.d/99-network-tuning.conf` on **epsilon AND culex** (either control-plane
   can run gluetun workloads), plus `tcp_bbr` in `/etc/modules-load.d/`:
   ```
   net.core.rmem_max=8388608
   net.core.wmem_max=8388608
   net.core.default_qdisc=fq
   net.ipv4.tcp_congestion_control=bbr
   ```
   Not GitOps-managed (node OS config); needs sudo.
2. **Revert `SERVER_COUNTRIES` Canada → Netherlands** — latency no longer matters with
   BBR+buffers, so restore the non-US exit for DMCA posture.
3. **`kubectl rollout restart deployment/arr-stack-ytdlpaas -n arr-stack`** — bring the
   other gluetun pod onto the working config.
4. Confirm both pods sustain high throughput; watch the backlog drain.
