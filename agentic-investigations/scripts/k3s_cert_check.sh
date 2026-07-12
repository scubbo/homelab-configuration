#!/bin/bash
# Read-only k3s certificate expiry check. Needs NO sudo and makes NO changes.
#
# Reports days-until-expiry for:
#   - the local ~/.kube/config client-admin cert (the one that dies with
#     "You must be logged in to the server ..." when it expires), and
#   - the live API serving cert on each server endpoint.
#
# Exits non-zero if anything is within $WARN_DAYS of expiry, so it can be wired
# into cron/a monitor later. See the runbook:
#   agentic-investigations/2026-07-12-k3s-client-cert-refresh.md
#
# Usage: ./k3s_cert_check.sh [warn_days]   (default warn_days=90)

set -euo pipefail

WARN_DAYS="${1:-90}"
SERVERS=("epsilon:6443" "culex:6443")

now_epoch=$(date +%s)
worst_ok=0  # becomes 1 if anything trips the warning

# Prints "<days> <notAfter>" for a PEM cert on stdin, or nothing on failure.
cert_days() {
  local enddate end_epoch
  enddate=$(openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//') || return 0
  [ -z "$enddate" ] && return 0
  # macOS/BSD date vs GNU date: try BSD form first, then GNU.
  end_epoch=$(date -j -f "%b %e %T %Y %Z" "$enddate" +%s 2>/dev/null \
    || date -d "$enddate" +%s 2>/dev/null) || return 0
  echo "$(( (end_epoch - now_epoch) / 86400 )) $enddate"
}

report() {
  local label="$1" days_line="$2"
  if [ -z "$days_line" ]; then
    printf '  %-34s UNKNOWN (could not read/parse cert)\n' "$label"
    return
  fi
  local days="${days_line%% *}" when="${days_line#* }"
  local flag=""
  if [ "$days" -lt 0 ]; then
    flag="  <-- EXPIRED"; worst_ok=1
  elif [ "$days" -lt "$WARN_DAYS" ]; then
    flag="  <-- WITHIN ${WARN_DAYS}d"; worst_ok=1
  fi
  printf '  %-34s %5s days left (%s)%s\n' "$label" "$days" "$when" "$flag"
}

echo "k3s certificate expiry (warn threshold: ${WARN_DAYS} days)"
echo

echo "Local kubeconfig client cert (~/.kube/config):"
client_pem=$(kubectl config view --raw \
  -o jsonpath='{.users[0].user.client-certificate-data}' 2>/dev/null | base64 -d 2>/dev/null || true)
if [ -n "$client_pem" ]; then
  report "client-admin (system:admin)" "$(printf '%s' "$client_pem" | cert_days)"
else
  echo "  UNKNOWN (no embedded client-certificate-data in current kubeconfig)"
fi
echo

echo "Live API serving certs:"
for s in "${SERVERS[@]}"; do
  pem=$(echo | openssl s_client -connect "$s" -servername kubernetes 2>/dev/null \
    | openssl x509 2>/dev/null || true)
  report "$s" "$(printf '%s' "$pem" | cert_days)"
done
echo

# ArgoCD keeps its OWN copy of the admin client cert in an argocd cluster secret. k3s
# rotation does not update it, so it can silently go stale (ArgoCD 401s while still
# showing "Healthy"). Surface it here. Needs read access to secrets in argocd (skipped
# gracefully if kubectl can't reach the cluster / lacks permission).
echo "ArgoCD in-cluster stored admin cert:"
argo_secret=$(kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$argo_secret" ]; then
  argo_pem=$(kubectl get secret "$argo_secret" -n argocd -o jsonpath='{.data.config}' 2>/dev/null \
    | base64 -d 2>/dev/null | jq -r '.tlsClientConfig.certData' 2>/dev/null \
    | base64 -d 2>/dev/null || true)
  report "$argo_secret" "$(printf '%s' "$argo_pem" | cert_days)"
else
  echo "  (skipped — kubectl could not read argocd cluster secret)"
fi

echo
if [ "$worst_ok" -ne 0 ]; then
  echo "RESULT: action needed — see the runbook to rotate/refresh."
  exit 1
fi
echo "RESULT: all certs healthy."
