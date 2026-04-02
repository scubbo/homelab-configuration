#!/usr/bin/env bash
# Periodically probes DNS resolution through multiple resolvers and methods,
# logging results to a CSV for later analysis of intermittent failures.

set -euo pipefail

LOG_DIR="${DNS_MONITOR_LOG_DIR:-$HOME/dns-monitor-logs}"
INTERVAL_SECONDS="${DNS_MONITOR_INTERVAL:-60}"

RESOLVERS=(
    "system"                # dig with no @server — uses /etc/resolv.conf
    "100.100.100.100"       # Tailscale MagicDNS
    "192.168.1.1"           # AdGuard Home (port 53)
    "192.168.1.1:5353"      # Unbound directly (port 5353)
    "8.8.8.8"               # Google Public DNS (external control)
)

EXTERNAL_TARGETS=(
    "google.com"
    "github.com"
    "duckduckgo.com"
    "one.one.one.one"       # Cloudflare — less likely to be blocked
)

INTERNAL_TARGETS=(
    "jellyfin.avril"
    "auth.avril"
)

ALL_TARGETS=("${EXTERNAL_TARGETS[@]}" "${INTERNAL_TARGETS[@]}")

# curl targets — test full system resolver + HTTP stack
CURL_TARGETS=(
    "https://google.com"
    "https://github.com"
    "https://duckduckgo.com"
    "https://jellyfin.avril"
)

mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/dns-probe-$(date +%Y%m%d).csv"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "timestamp,method,resolver,target,status,latency_ms,detail" > "$LOG_FILE"
fi

log_result() {
    local method="$1" resolver="$2" target="$3" status="$4" latency_ms="$5" detail="$6"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$method,$resolver,$target,$status,$latency_ms,$detail" >> "$LOG_FILE"
}

probe_dig() {
    local resolver="$1"
    local target="$2"
    local dig_args=("$target" "+time=5" "+tries=1" "+stats")

    if [[ "$resolver" == "system" ]]; then
        dig_args=("$target" "+time=5" "+tries=1" "+stats")
    elif [[ "$resolver" == *":"* ]]; then
        # resolver:port format
        local host="${resolver%%:*}"
        local port="${resolver##*:}"
        dig_args=("@$host" "-p" "$port" "$target" "+time=5" "+tries=1" "+stats")
    else
        dig_args=("@$resolver" "$target" "+time=5" "+tries=1" "+stats")
    fi

    local output
    if output=$(dig "${dig_args[@]}" 2>&1); then
        local status
        status=$(echo "$output" | awk '/status:/{for(i=1;i<=NF;i++) if($i ~ /status:/) {gsub(/,/,"",$((i+1))); print $((i+1)); exit}}')
        status="${status:-UNKNOWN}"
        local latency
        latency=$(echo "$output" | awk '/Query time:/{for(i=1;i<=NF;i++) if($i == "time:") {print $(i+1); exit}}')
        latency="${latency:-"-1"}"
        # Also capture the answer (resolved IPs)
        local answers
        answers=$(echo "$output" | awk '/^[^;].*IN[ \t]+A[ \t]/{print $NF}' | tr '\n' '|' | sed 's/|$//')
        log_result "dig" "$resolver" "$target" "$status" "$latency" "${answers:-no_answer}"
    else
        log_result "dig" "$resolver" "$target" "ERROR" "-1" "dig_failed"
    fi
}

# Tests the getaddrinfo() path — same as browsers and curl use internally.
# This is the critical probe: if dig works but this fails, the macOS system
# resolver or Tailscale's integration with it is the problem.
probe_getaddrinfo() {
    local target="$1"
    local output
    if output=$(python3 -c "
import socket, time
start = time.monotonic()
try:
    results = socket.getaddrinfo('$target', 443, socket.AF_INET, socket.SOCK_STREAM)
    elapsed_ms = int((time.monotonic() - start) * 1000)
    ips = '|'.join(sorted(set(r[4][0] for r in results)))
    print(f'OK {elapsed_ms} {ips}')
except socket.gaierror as e:
    elapsed_ms = int((time.monotonic() - start) * 1000)
    print(f'FAIL {elapsed_ms} {e}')
" 2>&1); then
        local status latency detail
        status=$(echo "$output" | awk '{print $1}')
        latency=$(echo "$output" | awk '{print $2}')
        detail=$(echo "$output" | cut -d' ' -f3-)
        log_result "getaddrinfo" "system" "$target" "$status" "$latency" "$detail"
    else
        log_result "getaddrinfo" "system" "$target" "ERROR" "-1" "python_failed"
    fi
}

# Checks the macOS DNS cache (dscacheutil) to see if a stale/bad entry is cached
probe_dscacheutil() {
    local target="$1"
    local output
    if output=$(dscacheutil -q host -a name "$target" 2>&1); then
        if [[ -z "$output" ]]; then
            log_result "dscacheutil" "cache" "$target" "MISS" "0" "not_cached"
        else
            local ips
            ips=$(echo "$output" | awk '/^ip_address:/{print $2}' | tr '\n' '|' | sed 's/|$//')
            local ipv6s
            ipv6s=$(echo "$output" | awk '/^ipv6_address:/{print $2}' | tr '\n' '|' | sed 's/|$//')
            local all_addrs="${ips}"
            [[ -n "$ipv6s" ]] && all_addrs="${all_addrs:+${all_addrs}|}${ipv6s}"
            log_result "dscacheutil" "cache" "$target" "HIT" "0" "${all_addrs:-no_ip}"
        fi
    else
        log_result "dscacheutil" "cache" "$target" "ERROR" "0" "command_failed"
    fi
}

probe_curl() {
    local url="$1"
    local curl_output http_code time_ms

    # Use curl's built-in timing — works reliably on macOS
    # Also capture DNS lookup time separately via time_namelookup
    if curl_output=$(curl -s -o /dev/null -w "%{http_code} %{time_total} %{time_namelookup} %{time_connect}" --connect-timeout 5 --max-time 10 "$url" 2>&1); then
        http_code=$(echo "$curl_output" | awk '{print $1}')
        time_ms=$(echo "$curl_output" | awk '{printf "%.0f", $2 * 1000}')
        local dns_ms connect_ms
        dns_ms=$(echo "$curl_output" | awk '{printf "%.0f", $3 * 1000}')
        connect_ms=$(echo "$curl_output" | awk '{printf "%.0f", $4 * 1000}')
        if [[ "$http_code" =~ ^[23] ]]; then
            log_result "curl" "system" "$url" "OK" "$time_ms" "http=${http_code}_dns=${dns_ms}ms_conn=${connect_ms}ms"
        else
            log_result "curl" "system" "$url" "HTTP_ERROR" "$time_ms" "http=${http_code}_dns=${dns_ms}ms_conn=${connect_ms}ms"
        fi
    else
        http_code=$(echo "$curl_output" | awk '{print $1}')
        time_ms=$(echo "$curl_output" | awk '{printf "%.0f", $2 * 1000}')
        local dns_ms connect_ms
        dns_ms=$(echo "$curl_output" | awk '{printf "%.0f", $3 * 1000}')
        connect_ms=$(echo "$curl_output" | awk '{printf "%.0f", $4 * 1000}')
        log_result "curl" "system" "$url" "CONNECT_FAIL" "${time_ms:-0}" "http=${http_code:-000}_dns=${dns_ms:-0}ms_conn=${connect_ms:-0}ms"
    fi
}

run_probes() {
    # dig probes — test each resolver directly
    for resolver in "${RESOLVERS[@]}"; do
        for target in "${ALL_TARGETS[@]}"; do
            probe_dig "$resolver" "$target"
        done
    done

    # getaddrinfo probes — test the OS resolver path (what browsers use)
    for target in "${ALL_TARGETS[@]}"; do
        probe_getaddrinfo "$target"
    done

    # dscacheutil probes — snapshot the macOS DNS cache state
    for target in "${ALL_TARGETS[@]}"; do
        probe_dscacheutil "$target"
    done

    # curl probes — test full HTTP connectivity
    for url in "${CURL_TARGETS[@]}"; do
        probe_curl "$url"
    done
}

echo "DNS monitor started. Logging to $LOG_FILE"
echo "Probing every ${INTERVAL_SECONDS}s. Press Ctrl+C to stop."
echo "Resolvers: ${RESOLVERS[*]}"
echo "Targets: ${ALL_TARGETS[*]}"
echo "Curl targets: ${CURL_TARGETS[*]}"

while true; do
    run_probes
    sleep "$INTERVAL_SECONDS"
done
