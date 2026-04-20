#!/bin/bash
# Monitors DNS resolution via OPNsense and correlates failures with ping.
# On each failure, logs both DNS and ping results so we can distinguish:
#   - Wi-Fi/LAN packet loss (both DNS and ping fail)
#   - DNS-specific hang in AdGuard Home or Unbound (ping fine, DNS fails)
#
# Usage: nohup ./dns_monitor.sh &>/tmp/dns_monitor_stdout.log &
# Log:   /tmp/dns_monitor.log

LOG=/tmp/dns_monitor.log
echo "=== DNS Monitor started $(date) ===" >> "$LOG"

while true; do
  ts=$(date +%H:%M:%S)
  dns=$(dig @192.168.1.1 github.com +short +time=2 +tries=1 2>&1)
  if echo "$dns" | grep -q "timed out\|connection timed out" || [ -z "$(echo "$dns" | grep -v '^;')" ]; then
    ping_result=$(ping -c1 -t1 192.168.1.1 2>&1 | grep -o "time=.*ms")
    echo "$ts | DNS=TIMEOUT | ping=${ping_result:-TIMEOUT}" | tee -a "$LOG"
  fi
  sleep 5
done
