# ESO vs VSO: Detailed Comparison

## TL;DR

**Current Choice:** Vault Secrets Operator (VSO)
**Reason:** Vault-only homelab, official HashiCorp support, better dynamic secrets integration

**When to Reconsider:** If we need to add other secret backends (AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, etc.)

---

## Quick Comparison Table

| Feature | External Secrets Operator (ESO) | Vault Secrets Operator (VSO) |
|---------|----------------------------------|------------------------------|
| **Vault Support** | Excellent ✅ | Excellent ✅ |
| **Other Backends** | Yes (AWS, GCP, Azure, 30+) ✅ | No ❌ |
| **Official Support** | Community (CNCF Sandbox) ⚠️ | HashiCorp ✅ |
| **Community Size** | Very Large 🌟🌟🌟 | Growing 🌟 |
| **Maturity** | Very Mature (v1.0+ since 2022) ✅ | Mature (v1.0+ since 2023) ✅ |
| **Dynamic Secrets** | Good ✅ | Better ✅✅ |
| **Vault Secret Engines** | All ✅ | All ✅ |
| **Learning Curve** | Moderate 📚 | Moderate 📚 |
| **Enterprise Support** | No ❌ | Yes ✅ |
| **Best For** | Multi-backend environments | Vault-only environments |

---

## External Secrets Operator (ESO)

### Overview

Community-driven, CNCF Sandbox project that provides a unified way to sync secrets from multiple external secret stores into Kubernetes.

### Supported Backends

- HashiCorp Vault
- AWS Secrets Manager
- AWS Parameter Store
- Google Secret Manager
- Azure Key Vault
- IBM Cloud Secrets Manager
- 1Password
- Doppler
- And 30+ more!

### Pros

✅ **Multi-backend flexibility** - Can switch between secret stores easily
✅ **Huge community** - ~4.3k GitHub stars, very active
✅ **CNCF project** - Neutral governance, no vendor lock-in
✅ **Extensive documentation** - Tons of examples and tutorials
✅ **Very mature** - Battle-tested in production across many companies
✅ **Regular updates** - Multiple releases per month
✅ **Supports all Vault secret engines** - KV, dynamic, PKI, transit, SSH, etc.
✅ **Multiple auth methods** - Kubernetes, AppRole, JWT, AWS IAM, GCP, Azure, certs, tokens

### Cons

❌ **No single vendor support** - Community-driven only
❌ **More abstraction layers** - SecretStore + ExternalSecret CRDs
❌ **Vault-specific features may lag** - Generic design means less Vault optimization
❌ **No official enterprise support contract** - Community Slack/GitHub only

### When to Use ESO

- You're using or planning to use multiple secret backends
- You want maximum flexibility to switch providers
- You value large community support over vendor support
- You're already using ESO elsewhere in your organization
- You might migrate from one cloud provider to another

---

## Vault Secrets Operator (VSO)

### Overview

Official HashiCorp operator specifically designed for syncing Vault secrets to Kubernetes. Purpose-built for Vault integration.

### Supported Backends

- HashiCorp Vault (only)

### Pros

✅ **Official HashiCorp support** - Enterprise support contracts available
✅ **Purpose-built for Vault** - Optimized for Vault workflows
✅ **Better dynamic secrets** - Native lease management and renewal
✅ **Vault-native concepts** - CRDs match Vault terminology
✅ **Simpler for Vault-only** - Less abstraction, more direct
✅ **Official documentation** - Authoritative HashiCorp docs
✅ **Future-proof** - Aligned with HashiCorp's roadmap
✅ **Supports all Vault secret engines** - KV, dynamic, PKI, transit, etc.

### Cons

❌ **Vault-only** - Cannot use other secret backends
❌ **Smaller community** - ~500 GitHub stars vs 4.3k for ESO
❌ **Younger project** - Released in 2022, less Stack Overflow content
❌ **Vendor lock-in** - Tied to HashiCorp Vault

### When to Use VSO

- You're 100% committed to Vault
- You want official vendor support
- You use dynamic secrets heavily
- You have HashiCorp support contracts
- You want tighter Vault integration
- Simpler mental model for Vault-only users

---

## Feature Comparison Details

### Secret Engine Support

**Both ESO and VSO support:**
- KV v1 and v2
- Dynamic secrets (Database, AWS, GCP, Azure)
- PKI (certificates)
- Transit (encryption as a service)
- SSH

**Key difference:** VSO has slightly better integration with Vault's lease system for dynamic secrets.

### Authentication Methods

**ESO supports:**
- Kubernetes (ServiceAccount)
- AppRole
- JWT/OIDC
- AWS IAM
- GCP
- Azure
- Certificate-based
- Token-based
- Basically everything Vault offers

**VSO supports:**
- Kubernetes (ServiceAccount) - PRIMARY
- JWT/OIDC
- AppRole
- AWS IAM
- Fewer options but covers most use cases

### Secret Rotation

**ESO:**
- Auto-refresh on configurable interval
- Detects Vault changes and updates K8s secrets
- Can trigger pod restarts (with reloader)

**VSO:**
- Native dynamic secret renewal
- Automatic lease renewal
- Better integration with Vault's lease system
- Can trigger pod restarts automatically

### Multi-tenancy

**Both support:**
- Multiple Vault instances
- Namespace-scoped configurations
- Cluster-scoped configurations

**ESO advantage:** Can connect to multiple different secret backends simultaneously

---

## Configuration Examples

### ESO Configuration

```yaml
# SecretStore - defines where secrets come from
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: my-app
spec:
  provider:
    vault:
      server: "https://vault.avril"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "my-app"
          serviceAccountRef:
            name: "default"

---
# ExternalSecret - defines what secrets to sync
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-secret
  namespace: my-app
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: my-k8s-secret
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: my-app/config
        property: password
```

### VSO Configuration

```yaml
# VaultAuth - defines how to authenticate
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: vault-auth
  namespace: my-app
spec:
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: my-app
    serviceAccount: default

---
# VaultStaticSecret - defines what secrets to sync
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: my-secret
  namespace: my-app
spec:
  vaultAuthRef: vault-auth
  mount: secret
  type: kv-v2
  path: my-app/config
  destination:
    name: my-k8s-secret
    create: true
  refreshAfter: 1h
```

**Observations:**
- Both require 2 resources (auth/store + secret definition)
- VSO uses more Vault-specific terminology
- ESO uses more generic terminology
- Configuration complexity is similar

---

## Maintenance & Community

### ESO

**GitHub Activity:**
- ~4,300 stars
- Very active - multiple releases per month
- Large contributor base
- Active Slack community
- Lots of blog posts and tutorials

**Governance:**
- CNCF Sandbox project (neutral)
- Multiple companies contributing
- Community-driven roadmap

### VSO

**GitHub Activity:**
- ~500 stars (growing)
- Active - regular releases
- Primarily HashiCorp maintainers
- HashiCorp Discuss forum
- Official HashiCorp tutorials

**Governance:**
- Official HashiCorp product
- HashiCorp-driven roadmap
- Enterprise support available

---

## Migration Path

### From VSO to ESO

**Effort:** Moderate
**Reason:** Both create standard Kubernetes Secrets, so apps don't change. Only CRDs need updating.

**Steps:**
1. Install ESO alongside VSO
2. Create SecretStore CRDs
3. Create ExternalSecret CRDs matching your VaultStaticSecret CRDs
4. Verify secrets are created correctly
5. Delete VSO CRDs
6. Uninstall VSO

### From ESO to VSO

**Effort:** Moderate
**Reason:** Same as above - only infrastructure changes, not applications.

**Steps:**
1. Install VSO alongside ESO
2. Create VaultAuth CRDs
3. Create VaultStaticSecret CRDs matching your ExternalSecret CRDs
4. Verify secrets are created correctly
5. Delete ESO CRDs
6. Uninstall ESO

**Gotcha:** If using non-Vault backends in ESO, you can't migrate those to VSO!

---

## Decision Matrix

### Choose ESO if:

- [ ] You use or plan to use multiple secret backends (AWS, GCP, Azure, etc.)
- [ ] You might switch cloud providers or secret stores
- [ ] You value maximum community support
- [ ] You already use ESO elsewhere
- [ ] You want vendor-neutral solution (CNCF)
- [ ] You need the broadest possible authentication options

### Choose VSO if:

- [x] You're committed to HashiCorp Vault long-term ← **This is us!**
- [x] You want official vendor support ← **This is us!**
- [x] You use dynamic secrets extensively ← **Might do this!**
- [x] You have or want HashiCorp support contracts
- [x] You prefer Vault-native terminology and concepts
- [x] You want simpler setup for Vault-only use case ← **This is us!**

---

## Our Decision: VSO

### Rationale

1. **Vault-only commitment** - We're only using Vault, no plans for other backends
2. **Official support** - Nice to have authoritative HashiCorp docs
3. **Dynamic secrets future** - Better support when we add this later
4. **Simplicity** - Purpose-built for our use case
5. **Jack's prior experience** - Already used it successfully (blog post: https://blog.scubbo.org/posts/vault-secrets-into-k8s/)

### When to Reconsider

We should revisit this decision if:

- We start using AWS and want AWS Secrets Manager integration
- We need GCP Secret Manager for GCP resources
- We want to experiment with multiple secret backends
- We need features that ESO has but VSO doesn't
- We want to contribute to a CNCF project vs vendor product

---

## References

- [External Secrets Operator Docs](https://external-secrets.io/)
- [Vault Secrets Operator Docs](https://developer.hashicorp.com/vault/docs/platform/k8s/vso)
- [Jack's VSO Blog Post](https://blog.scubbo.org/posts/vault-secrets-into-k8s/)
- [ESO GitHub](https://github.com/external-secrets/external-secrets)
- [VSO GitHub](https://github.com/hashicorp/vault-secrets-operator)

---

## Last Updated

2025-11-29 - Initial comparison based on current state of both operators
