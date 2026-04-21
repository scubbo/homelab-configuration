# Intermittent DNS Failures (2026-04-17)

## Symptoms
- Laptop intermittently cannot resolve external domains (github.com, google.com, amazonaws.com, claude.ai, news.ycombinator.com)
- Browser shows "unable to connect"
- `flush_cache` (macOS DNS cache flush) fixes it temporarily, returns in 10 min–1 hr
- NOT a pod-level issue — affects the laptop directly

## DNS chain
Client → macOS mDNSResponder → AdGuard Home @ 192.168.1.1:53 → Unbound @ 192.168.1.1:5353 → upstream

macOS resolver config (scutil --dns):
- Resolver #1 (order 100600): Tailscale MagicDNS 100.100.100.100 — Supplemental, only handles `coin-pangolin.ts.net` and `avril`
- Resolver #2 (order 200000): 192.168.1.1 — default for all other queries

## Root cause: AdGuard Home query log file accumulation

**`querylog.json` was 7.8GB; `querylog.json.1` was 9.0GB.**

AdGuard Home was configured with `querylog.interval: 2160h` (90 days retention) and `size_memory: 1000`. When 1000 in-memory query log entries accumulated, AdGuard Home flushed them to the 7.8GB file. The I/O pause during this flush briefly froze DNS query processing, causing connection timeouts from the client's perspective. macOS mDNSResponder cached the failure, causing sustained browser errors until `flush_cache`.

This matches the ~60-second failure periodicity seen in the monitor log: the 1000-entry buffer filled and flushed roughly every minute.

**Secondary issue:** `cache_enabled: false` combined with `ratelimit: 20` (per /24 subnet). With no DNS cache, every query hits Unbound and counts against the rate limit. A single page load can fire 20+ DNS queries simultaneously, exhausting the limit and dropping queries.

## Resolution

On OPNsense:

```bash
service adguardhome stop
truncate -s 0 /usr/local/AdGuardHome/data/querylog.json
truncate -s 0 /usr/local/AdGuardHome/data/querylog.json.1
# edit AdGuardHome.yaml (see below)
service adguardhome start
```

Changes to `/usr/local/AdGuardHome/AdGuardHome.yaml`:

```yaml
querylog:
  interval: 168h      # was 2160h (90 days) — 7 days is plenty

dns:
  cache_enabled: true   # was false
  cache_size: 4194304   # 4MB
```

## Ruled out
- CoreDNS (k8s) — healthy, no errors
- External-dns — running fine
- ProtonVPN DNS interference — no custom DNS set on ProtonVPN interface
- AdGuard Home crash-loop — binary is v0.107.73 (correct), process stable since 2026-04-09
- Unbound errors — resolver logs show no errors
- Wi-Fi/LAN packet loss — confirmed by monitor: ping to 192.168.1.1 always succeeds during DNS failures

## Monitor data (2026-04-20)
Background monitor ran for ~24h logging DNS failures with simultaneous ping to OPNsense.
- Every DNS failure: ping succeeded (1–8ms typical) → conclusively ruled out network/LAN issues
- Failure pattern: roughly every 60 seconds within failure windows, ~10 min clean gaps between windows
- Two failure modes: `TIMEOUT` (no UDP response) and `EMPTY/SERVFAIL` (response with no answer)
- Monitor script: `agentic-investigations/scripts/dns_monitor.sh`

## OPNsense file locations
- AdGuard Home binary: `/usr/local/AdGuardHome/AdGuardHome` (v0.107.73)
- AdGuard Home config: `/usr/local/AdGuardHome/AdGuardHome.yaml`
- AdGuard Home query log: `/usr/local/AdGuardHome/data/querylog.json` (truncate if re-accumulating)
- Resolver (Unbound) logs: `/var/log/resolver/resolver_YYYYMMDD.log`
- AdGuard Home HTTP API: `http://192.168.1.1:3000` (requires auth, user: adguard)

## If this recurs
1. Check querylog.json size: `ls -lh /usr/local/AdGuardHome/data/`
2. If large (>100MB), stop adguardhome, truncate, restart
3. Check monitor log: `cat /tmp/dns_monitor.log` (restart monitor if not running — see script above)
4. Verify AdGuard Home config hasn't reverted: `grep -A3 "querylog:" /usr/local/AdGuardHome/AdGuardHome.yaml`
