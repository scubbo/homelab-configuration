# Homelab Prerequisites

This document describes the prerequisites that must be installed before deploying applications via ArgoCD.

## Storage Provisioners

### democratic-csi

democratic-csi provides dynamic storage provisioning using TrueNAS/FreeNAS. It must be installed separately via Helm before deploying applications that require dynamic PVCs.

#### Installation

**TrueNAS Configuration:**
- TrueNAS version: 13.0-U5.3 or compatible
- SSH access configured with key-based authentication
- API key generated for HTTP access
- ZFS datasets created:
  - iSCSI: `high-resiliency/k8s/iscsi/vols` (volumes)
  - iSCSI: `high-resiliency/k8s/iscsi/snaps` (snapshots)
  - NFS: `high-resiliency/k8s/nfs/vols` (volumes)
  - NFS: `high-resiliency/k8s/nfs/snaps` (snapshots)

**Helm Installation:**

Add the democratic-csi Helm repository:
```bash
helm repo add democratic-csi https://democratic-csi.github.io/charts/
helm repo update
```

Install the iSCSI driver:
```bash
helm install zfs-iscsi democratic-csi/democratic-csi \
  --version 0.14.7 \
  --namespace democratic-csi \
  --create-namespace \
  --values values-iscsi.yaml
```

Install the NFS driver:
```bash
helm install zfs-nfs democratic-csi/democratic-csi \
  --version 0.14.7 \
  --namespace democratic-csi \
  --values values-nfs.yaml
```

**Important:** Pin both the chart version (0.14.7) and the driver image to a specific SHA to avoid breakage from automatic updates:

```yaml
# In your values file:
controller:
  driver:
    image: docker.io/democraticcsi/democratic-csi@sha256:7fffba3553a0613c9b2c709588d5658cdc80b0126c9157318224228d8a5f7d35
    imagePullPolicy: IfNotPresent

node:
  driver:
    image: docker.io/democraticcsi/democratic-csi@sha256:7fffba3553a0613c9b2c709588d5658cdc80b0126c9157318224228d8a5f7d35
    imagePullPolicy: IfNotPresent
```

This SHA corresponds to the `next` tag as of December 2025, which includes fixes for:
- TrueNAS 13.0 compatibility
- NFS share creation API changes
- Response body handling improvements

**Configuration Example (NFS):**

See the full configuration in use by running:
```bash
helm get values zfs-nfs -n democratic-csi
```

Key configuration sections:
- `driver.config.driver`: `freenas-nfs`
- `driver.config.httpConnection`: TrueNAS API connection details
- `driver.config.sshConnection`: SSH connection with private key
- `driver.config.nfs`: NFS share settings
- `driver.config.zfs`: ZFS dataset configuration

**Verification:**

Check that the storage classes are available:
```bash
kubectl get storageclass
```

Expected output:
```
NAME                   PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
freenas-iscsi-csi      org.democratic-csi.iscsi   Delete          Immediate              true
freenas-nfs-csi        org.democratic-csi.nfs     Delete          Immediate              true
```

**Troubleshooting:**

If PVC creation fails with "Cannot read properties of undefined" errors:
1. Verify TrueNAS is accessible via SSH and HTTP API
2. Check that the image SHA includes recent fixes (use SHA above or newer)
3. Review controller logs: `kubectl logs -n democratic-csi <pod-name> -c csi-driver`
4. See GitHub issues: https://github.com/democratic-csi/democratic-csi/issues

#### Upgrading

To upgrade to a newer version:

1. Find the current SHA in use:
```bash
kubectl get pod -n democratic-csi -o jsonpath='{.items[?(@.metadata.name contains "controller")].status.containerStatuses[?(@.name=="csi-driver")].imageID}'
```

2. Identify the target SHA from Docker Hub or GitHub
3. Update your values file with the new SHA
4. Upgrade the Helm release:
```bash
helm upgrade zfs-nfs democratic-csi/democratic-csi \
  --version 0.14.7 \
  --namespace democratic-csi \
  --values values-nfs.yaml
```

**Note:** Always specify the chart version to prevent unexpected template changes.

**Note:** Upgrading the CSI driver does not affect existing mounted volumes, but may briefly impact new volume provisioning during the upgrade.

## Other Prerequisites

(Add other prerequisites as needed)
