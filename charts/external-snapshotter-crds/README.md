These files are snapshots (a-ha) of the Kubernetes manifests that define the `external-snapshotter` CRDs (since Argo doesn't support defining an application from web-hosted manifests).

```bash
$ curl --silent "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-5.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml" -o volumesnapshotclasses.yaml

$ curl --silent "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-5.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml" -o volumesnapshotcontents.yaml

$ curl --silent "https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-5.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml" -o volumesnapshots.yaml
```