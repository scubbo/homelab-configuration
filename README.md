This repo stores the configuration used to define my homelab.

# History

Since 2023, I'd been self-hosting a Gitea instance that was used as the source both for configuration, and (for applications I wrote myself) for source code. In July 2025, a hard-drive failure prompted me to rebuild the cluster from the ground up, and I re-evaluated that choice.

Although I still conceptually agree with the reasons that led me to self-host a Git forge (centralization of development services, especially when owned by BigTech, leads to stagnation and exploitation), in practice my Gitea instance:
* was the most fragile/error-prone applications on the homelab - I've lost count of the number of times I had to simply tear it down and reinstall from scratch, resubmitting Git repos from local backups
* as such, was the biggest impediment to development on other interesting topics - if you can't work with source code, you can't really get _anything_ done.
* wasn't really doing a good job of _teaching_ me anything; and, in some cases, was actively holding me back from working on practices useful in other areas (like using GitHub's OIDC with Vault - at the time of writing, my PR to add that feature to Gitea is still languishing)

So - with some regret and shame - I've decided it's prudent to conform and use the industry standard; _[So I packed all my pamphlets with my bibles at the back of the shelf](https://frank-turner.com/tracks/love-ire-song/)_.

# Auxillary installations

Several applications in this setup depend on [democratic-csi](https://github.com/democratic-csi/democratic-csi/), an automatic provisioner of PersistentVolumes from (among other things) `freenas-nfs` and `freenas-iscsi`. Unfortunately there's no easy way to model this within the app-of-apps setup here for one-command installation, as the `values.yaml` include both an `apiKey` and an ssh key, both of which should be treated as secrets. Thankfully, installation is reasonably well-documented - a combination of [these](https://jonathangazeley.com/2021/01/05/using-truenas-to-provide-persistent-storage-for-kubernetes/) [two](https://www.lisenet.com/2021/moving-to-truenas-and-democratic-csi-for-kubernetes-persistent-storage/) community guides suffice for setting up the FreeNAS server to accept connections, and there's a great `values.yaml` template [here](https://raw.githubusercontent.com/democratic-csi/charts/master/stable/democratic-csi/examples/freenas-nfs.yaml) which needs values filled in from the appropriate [examples](https://github.com/democratic-csi/democratic-csi/tree/master/examples). Remember to adjust:
* `host`
* Use `apiKey` instead of `username/password`
* `datasetParentName` and `detachedSnapshotsDatasetParentName` - for myself, they were `high-resiliency/k8s/[nfs|iscsi]/[vols|snaps]`, where `high-resiliency` was the name of the pool I made
* `nfs.shareHost`
* the `port` for `iscsi.targetPortal` is, by-default, `3260`

## ArgoCD

ArgoCD is installed via Helm (not managed by app-of-apps due to the chicken-and-egg problem):

```bash
helm install argo-cd argo-cd --repo https://argoproj.github.io/argo-helm -n argocd --create-namespace
```

### OIDC Authentication with Authentik

ArgoCD is configured to use Authentik for SSO via Dex. Setup requires:

1. **Create Authentik Application/Provider:**
   - Application name: `ArgoCD`, slug: `argocd`
   - Provider type: OAuth2/OIDC, Client type: Confidential
   - Redirect URIs: `https://argo.avril/api/dex/callback` and `http://localhost:8085/auth/callback`
   - Authorization flow: `implicit-consent`

2. **Create K8s secret with client secret:**
   ```bash
   kubectl patch secret argocd-secret -n argocd --type merge -p '{"stringData": {"dex.authentik.clientSecret": "YOUR_SECRET"}}'
   ```

3. **Upgrade with OIDC values:**
   ```yaml
   configs:
     cm:
       url: https://argo.avril
       dex.config: |
         connectors:
           - type: oidc
             id: authentik
             name: Authentik
             config:
               issuer: https://auth.avril/application/o/argo-cd/
               clientID: <from authentik>
               clientSecret: $dex.authentik.clientSecret
               insecureEnableGroups: true
               scopes:
                 - openid
                 - profile
                 - email
   ```
