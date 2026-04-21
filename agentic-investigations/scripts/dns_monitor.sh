#!/bin/bash
# Monitors DNS resolution via OPNsense and correlates failures with ping.
# On each failure, logs both DNS response code and ping so we can distinguish:
#   - Wi-Fi/LAN packet loss (both DNS and ping fail)
#   - DNS-specific hang (ping fine, DNS TIMEOUT)
#   - SERVFAIL from upstream (ping fine, DNS SERVFAIL)
#   - Blocked/NXDOMAIN (ping fine, DNS NXDOMAIN)
#
# Usage: nohup ./dns_monitor.sh &>/tmp/dns_monitor_stdout.log &
# Log:   /tmp/dns_monitor.log

LOG=/tmp/dns_monitor.log
echo "=== DNS Monitor started $(date) ===" >> "$LOG"

while true; do
  ts=$(date +%H:%M:%S)
  full=$(dig @192.168.1.1 github.com +time=2 +tries=1 2>&1)
  rcode=$(echo "$full" | grep "status:" | sed 's/.*status: \([A-Z]*\).*/\1/')
  answer=$(echo "$full" | grep -A1 "ANSWER SECTION" | grep -v "ANSWER SECTION" | head -1)

  if echo "$full" | grep -q "timed out\|connection timed out"; then
    ping_result=$(ping -c1 -t1 192.168.1.1 2>&1 | grep -o "time=.*ms")
    echo "$ts | DNS=TIMEOUT | ping=${ping_result:-TIMEOUT}" | tee -a "$LOG"
  elif [ "$rcode" != "NOERROR" ] || [ -z "$answer" ]; then
    ping_result=$(ping -c1 -t1 192.168.1.1 2>&1 | grep -o "time=.*ms")
    echo "$ts | DNS=${rcode:-EMPTY} | ping=${ping_result:-TIMEOUT}" | tee -a "$LOG"
  fi
  sleep 5
done
