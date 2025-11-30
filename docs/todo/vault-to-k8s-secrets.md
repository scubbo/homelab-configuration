# Vault to Kubernetes Secrets Integration

## Overview

Currently, all secrets in the homelab cluster are managed manually as Kubernetes Secret resources. This TODO describes implementing proper Vault integration using **Vault Secrets Operator (VSO)** to automatically sync secrets from Vault into Kubernetes.

**Reference:** Jack's blog post on this topic: https://blog.scubbo.org/posts/vault-secrets-into-k8s/

**Why VSO instead of External Secrets Operator (ESO)?**
- VSO is HashiCorp's official operator for Vault
- Better dynamic secrets integration with Vault's lease system
- Jack has already successfully implemented this approach (see blog post above)
- Simpler configuration for Vault-only use case
- Official HashiCorp support available
- See [docs/todo/eso-vs-vso-comparison.md](eso-vs-vso-comparison.md) for detailed comparison

## Current State

**What we have:**
- Vault deployed at `https://vault.avril` (via `/app-of-apps/vault.jsonnet`)
- Vault initialized and configured with:
  - GitHub Secrets Plugin (for GitHub Actions OIDC)
  - `auth/userpass/` authentication
  - `auth/jwt/` for GitHub Actions
  - File storage backend

**What we're doing now:**
- Manually creating Kubernetes Secrets with `kubectl create secret`
- Kyverno policies inject secrets into pods (see `/manifests/gluetun/kyverno-gluetun-inject.yaml`)
- Apps reference secrets via `secretKeyRef` (see `/app-of-apps/immich.jsonnet`)

**Examples of manual secrets:**
- `cloudflare-api-key-secret` (cert-manager)
- `gluetun-protonvpn` (VPN credentials)
- `immich-database-app` (PostgreSQL password)
- `nzbget-creds` (arr-stack)
- `opnsense-api-credentials` (external-dns) - newly added

## Goal

Automate secret management so that:
1. Secrets are stored in Vault (single source of truth)
2. Kubernetes automatically pulls secrets from Vault
3. Secrets auto-update when changed in Vault
4. No manual `kubectl create secret` commands needed

## Implementation Plan

### Phase 1: Install Vault Secrets Operator

**What:** Deploy VSO to the cluster

**How:**
1. Add VSO to ArgoCD app-of-apps:
   ```jsonnet
   // In app-of-apps/vault-secrets-operator.jsonnet
   appDefinitions.helmApplication(
     name='vault-secrets-operator',
     sourceRepoUrl='https://helm.releases.hashicorp.com',
     sourceChart='vault-secrets-operator',
     sourceTargetRevision='0.10.0',  // Check for latest version
     namespace='vault-secrets-operator-system',
     helmValues={
       defaultVaultConnection: {
         enabled: true,
         address: 'https://vault.avril',
         skipTLSVerify: true  // If using self-signed certs
       }
     }
   )
   ```

2. Deploy and verify:
   ```bash
   kubectl get pods -n vault-secrets-operator-system
   ```

**Reference:** https://developer.hashicorp.com/vault/docs/platform/k8s/vso

### Phase 2: Configure Vault Kubernetes Auth

**What:** Set up Vault to authenticate Kubernetes service accounts

**How:**
1. Enable Kubernetes auth in Vault:
   ```bash
   vault auth enable kubernetes
   ```

2. Configure Kubernetes auth method:
   ```bash
   vault write auth/kubernetes/config \
     kubernetes_host="https://epsilon:6443" \
     kubernetes_ca_cert=@/path/to/ca.crt \
     token_reviewer_jwt=@/path/to/reviewer-token
   ```

3. Create policies for each application namespace:
   ```hcl
   # Example policy for arr-stack
   path "secret/data/arr-stack/*" {
     capabilities = ["read"]
   }
   ```

4. Create Vault roles for each namespace:
   ```bash
   vault write auth/kubernetes/role/arr-stack \
     bound_service_account_names=external-secrets \
     bound_service_account_namespaces=arr-stack \
     policies=arr-stack-policy \
     ttl=24h
   ```

**Reference:** https://developer.hashicorp.com/vault/docs/auth/kubernetes

### Phase 3: Create Secret Stores

**What:** Create SecretStore resources in each namespace

**How:**
1. Create a SecretStore per namespace (or a ClusterSecretStore):
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: SecretStore
   metadata:
     name: vault-backend
     namespace: arr-stack
   spec:
     provider:
       vault:
         server: "https://vault.avril"
         path: "secret"
         version: "v2"
         auth:
           kubernetes:
             mountPath: "kubernetes"
             role: "arr-stack"
             serviceAccountRef:
               name: "external-secrets"
   ```

2. Could use Kyverno to auto-generate these per namespace (similar to current gluetun pattern)

### Phase 4: Migrate Secrets to Vault

**What:** Move existing secrets into Vault

**How:**
1. For each secret, extract current value:
   ```bash
   kubectl get secret cloudflare-api-key-secret -n security -o jsonpath='{.data.apiKey}' | base64 -d
   ```

2. Store in Vault:
   ```bash
   vault kv put secret/security/cloudflare apiKey=<value>
   ```

3. Organize secrets by namespace:
   - `secret/security/*` - cert-manager, vault, etc.
   - `secret/arr-stack/*` - nzbget, etc.
   - `secret/vpn/*` - gluetun credentials
   - `secret/media/*` - immich, jellyfin, etc.

### Phase 5: Create ExternalSecret Resources

**What:** Define ExternalSecret CRDs to pull from Vault

**How:**
1. Replace manual secrets with ExternalSecret definitions:
   ```yaml
   apiVersion: external-secrets.io/v1beta1
   kind: ExternalSecret
   metadata:
     name: cloudflare-api-key-secret
     namespace: security
   spec:
     refreshInterval: 1h
     secretStoreRef:
       name: vault-backend
       kind: SecretStore
     target:
       name: cloudflare-api-key-secret
       creationPolicy: Owner
     data:
       - secretKey: apiKey
         remoteRef:
           key: security/cloudflare
           property: apiKey
   ```

2. Deploy these as part of each app's manifests

### Phase 6: Update Applications

**What:** Ensure apps can still reference secrets (they shouldn't need changes!)

**How:**
- ExternalSecret creates regular Kubernetes Secrets with same names
- Apps continue using `secretKeyRef` as before
- No application changes needed!

### Phase 7: Optional Enhancements

**Kyverno Integration:**
- Auto-generate ServiceAccounts for ESO in each namespace
- Auto-create SecretStore resources in labeled namespaces
- Similar to current gluetun injection pattern

**Secret Rotation:**
- Configure automatic rotation for sensitive credentials
- Use Vault's dynamic secrets where applicable

## Migration Strategy

**Approach:** Gradual migration, one namespace at a time

1. Start with a non-critical namespace (e.g., `arr-stack`)
2. Verify ESO is working correctly
3. Migrate more critical services (immich, etc.)
4. Finally migrate infrastructure secrets (cert-manager, etc.)

**Rollback:** Keep manual secrets in place until ESO-managed secrets are confirmed working

## Secrets to Migrate

Based on current codebase analysis:

| Secret Name | Namespace | Used By | Priority |
|-------------|-----------|---------|----------|
| `nzbget-creds` | `arr-stack` | arr-stack | Low (good test case) |
| `gluetun-protonvpn` | `vpn` | gluetun | Medium |
| `immich-database-app` | `media` | immich | Medium |
| `cloudflare-api-key-secret` | `security` | cert-manager | High (critical!) |
| `opnsense-api-credentials` | TBD | external-dns | Medium |

## Testing

1. Deploy ESO to dev/test namespace first
2. Create a test secret in Vault
3. Create test ExternalSecret
4. Verify Kubernetes Secret is created
5. Verify secret updates when Vault changes
6. Test with actual application

## References

- [External Secrets Operator Docs](https://external-secrets.io/)
- [Vault Kubernetes Auth](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
- [ESO Vault Provider](https://external-secrets.io/latest/provider/hashicorp-vault/)
- [Existing TODO in gluetun README](/manifests/gluetun/README.md)

## Estimated Effort

- **Setup (Phases 1-3):** 2-4 hours
- **Migration per namespace (Phases 4-5):** 30 min - 1 hour
- **Testing & validation:** 1-2 hours
- **Total:** 4-8 hours depending on number of secrets

## Notes

- This was originally planned in `/manifests/gluetun/README.md` but never implemented
- Current Kyverno patterns can be leveraged for auto-generating ESO resources
- Vault is already running and ready to use
- No application code changes needed - just infrastructure
