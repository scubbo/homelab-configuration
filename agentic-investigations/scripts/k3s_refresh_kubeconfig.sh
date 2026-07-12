#!/bin/bash
# Refresh laptop k3s credentials after the client-admin cert has (or is about to)
# expire. Pulls a fresh kubeconfig off the primary server, rewrites the server
# address, preserves the working namespace, installs it, verifies, and re-logins
# argocd.
#
# By default this ONLY touches the laptop (no cluster changes) and assumes the
# on-disk leaf certs are still valid — e.g. you ran `k3s certificate rotate`
# by hand, or the certs simply auto-rotated on a restart.
#
# It ALSO refreshes ArgoCD's own stored copy of the admin client cert (in the
# argocd `cluster-*` secret) and restarts the application controller. Rotating
# k3s does NOT update that copy, so after a rotation ArgoCD 401s against the API
# while still showing a stale "Healthy" — this is the fix. Skip with --no-argocd.
#
# With --rotate it also drives the on-node rotation on BOTH servers, sequentially
# and HA-safely (rotate primary -> refresh laptop creds -> verify -> rotate
# secondary -> verify). The on-node steps use `ssh -t` so interactive sudo can
# prompt for your password (sudo is NOT passwordless on these hosts).
#
# Full context + the manual equivalent of every step:
#   agentic-investigations/2026-07-12-k3s-client-cert-refresh.md
#
# Usage:
#   ./k3s_refresh_kubeconfig.sh                 # laptop-only refresh from epsilon
#   ./k3s_refresh_kubeconfig.sh --rotate        # also rotate certs on epsilon + culex
#   ./k3s_refresh_kubeconfig.sh --no-argocd     # skip the argocd re-login
#   ./k3s_refresh_kubeconfig.sh --server culex  # pull kubeconfig from a different primary
#
# Env overrides: PRIMARY, SECONDARY, SSH_USER, ARGOCD_SERVER, STAGE_PATH

set -euo pipefail

PRIMARY="${PRIMARY:-epsilon}"       # server whose kubeconfig we pull (= cluster endpoint)
SECONDARY="${SECONDARY:-culex}"     # other control-plane, rotated too under --rotate
SSH_USER="${SSH_USER:-scubbo}"
ARGOCD_SERVER="${ARGOCD_SERVER:-argo.scubbo.org}"
STAGE_PATH="${STAGE_PATH:-/tmp/k3s-fresh.yaml}"
PORT=6443

DO_ROTATE=0
DO_ARGOCD=1
while [ $# -gt 0 ]; do
  case "$1" in
    --rotate)    DO_ROTATE=1 ;;
    --no-argocd) DO_ARGOCD=0 ;;
    --server)    shift; PRIMARY="$1" ;;
    -h|--help)   grep '^#' "$0" | grep -v '^#!' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# Wait until host:6443 accepts TCP connections (API back up after a restart).
wait_api() {
  local host="$1" tries=60
  while [ "$tries" -gt 0 ]; do
    if (exec 3<>"/dev/tcp/$host/$PORT") 2>/dev/null; then exec 3>&- 3<&-; return 0; fi
    sleep 2; tries=$((tries - 1))
  done
  echo "timed out waiting for $host:$PORT to come back up" >&2; return 1
}

# stop k3s -> rotate on-disk leaf certs -> start k3s, on one host. Interactive sudo.
rotate_node() {
  local host="$1"
  say "Rotating certs on $host (sudo will prompt) — ~30-60s API blip"
  ssh -t "${SSH_USER}@${host}" \
    'sudo systemctl stop k3s && sudo k3s certificate rotate && sudo systemctl start k3s'
  wait_api "$host"
}

# Pull the fresh kubeconfig off PRIMARY, rewrite + install it on the laptop, verify.
refresh_local_kubeconfig() {
  say "Staging fresh kubeconfig on ${PRIMARY} (sudo will prompt)"
  ssh -t "${SSH_USER}@${PRIMARY}" \
    "sudo install -m 600 -o \"\$USER\" /etc/rancher/k3s/k3s.yaml ${STAGE_PATH}"

  local tmp; tmp=$(mktemp)
  say "Copying ${PRIMARY}:${STAGE_PATH} -> laptop"
  scp "${SSH_USER}@${PRIMARY}:${STAGE_PATH}" "$tmp"

  # Preserve whatever namespace the current context uses (reads the file, works
  # even when creds are expired); fall back to arr-stack.
  local ns; ns=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)
  ns="${ns:-arr-stack}"

  # The k3s.yaml always points at 127.0.0.1; the laptop reaches it as ${PRIMARY}.
  sed -i.orig "s#server: https://127.0.0.1:${PORT}#server: https://${PRIMARY}:${PORT}#" "$tmp"
  rm -f "${tmp}.orig"

  local kube="$HOME/.kube/config"
  if [ -f "$kube" ]; then
    local bak="${kube}.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$kube" "$bak"
    say "Backed up existing kubeconfig -> $bak"
  fi
  mkdir -p "$HOME/.kube"
  install -m 600 "$tmp" "$kube"
  rm -f "$tmp"

  kubectl config set-context --current --namespace="$ns" >/dev/null
  say "Installed kubeconfig (server=${PRIMARY}:${PORT}, namespace=${ns}); verifying"
  kubectl get nodes

  say "Cleaning up ${STAGE_PATH} on ${PRIMARY} (holds admin creds)"
  ssh "${SSH_USER}@${PRIMARY}" "rm -f ${STAGE_PATH}"
}

# ArgoCD authenticates to the cluster with its OWN copy of the admin client cert,
# held in the argocd `cluster-*` secret at .data.config -> tlsClientConfig.{certData,keyData}.
# k3s rotation does not touch it, so it goes stale (ArgoCD 401s under a stale "Healthy").
# Copy the fresh cert/key from the just-installed kubeconfig in and bounce the controller.
refresh_argocd_cluster_cert() {
  local ns=argocd want="https://${PRIMARY}:${PORT}" secret="" s
  for s in $(kubectl get secrets -n "$ns" -l argocd.argoproj.io/secret-type=cluster \
               -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    if [ "$(kubectl get secret "$s" -n "$ns" -o jsonpath='{.data.server}' | base64 -d)" = "$want" ]; then
      secret="$s"; break
    fi
  done
  if [ -z "$secret" ]; then
    echo "WARN: no argocd cluster secret targets ${want}; skipping in-cluster cert refresh" >&2
    return 0
  fi
  say "Refreshing ArgoCD's in-cluster admin cert (secret ${secret})"
  # kubeconfig stores cert/key as base64(PEM); argocd's certData/keyData use the same
  # encoding, so they copy across verbatim.
  local certB64 keyB64 new_cfg
  certB64=$(kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}')
  keyB64=$(kubectl config view --raw -o jsonpath='{.users[0].user.client-key-data}')
  new_cfg=$(kubectl get secret "$secret" -n "$ns" -o jsonpath='{.data.config}' | base64 -d \
    | jq --arg c "$certB64" --arg k "$keyB64" \
        '.tlsClientConfig.certData=$c | .tlsClientConfig.keyData=$k' \
    | base64 | tr -d '\n')
  kubectl patch secret "$secret" -n "$ns" --type merge \
    -p "$(jq -cn --arg cfg "$new_cfg" '{data:{config:$cfg}}')"
  say "Restarting argo-cd-argocd-application-controller so it reconnects"
  kubectl rollout restart statefulset argo-cd-argocd-application-controller -n "$ns"
}

if [ "$DO_ROTATE" -eq 1 ]; then
  rotate_node "$PRIMARY"          # 1. rotate the endpoint node
  refresh_local_kubeconfig        # 2. get working laptop creds before verifying more
  rotate_node "$SECONDARY"        # 3. now HA-rotate the other control plane
  say "Confirming both nodes Ready after rotation"
  kubectl get nodes
else
  refresh_local_kubeconfig
fi

if [ "$DO_ARGOCD" -eq 1 ]; then
  refresh_argocd_cluster_cert     # the important, easily-missed one (masked "Healthy")
  say "Re-logging into argocd CLI (${ARGOCD_SERVER}) via SSO — opens a browser"
  argocd login "$ARGOCD_SERVER" --grpc-web --sso
fi

say "Done. 'kubectl get nodes' and 'argocd app list' should both work now."
