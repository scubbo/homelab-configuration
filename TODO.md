Scattered TODOs that either don't belong in any particular application, or that I was just too lazy to place there:

- [ ] Try updating Sonarr (if the issue noted in `values.yaml` has been resolved)
- [X] Move Readarr config onto `iscsi` (NFS seems not to play nice with SQLite), then use [rreading-glasses](https://github.com/blampe/rreading-glasses#usage)
- [ ] MySQL database for Ombi
- [X] Correct the names back from "Overseerr" to "Ombi" - turns out I forgot to swap the images in the first place!
- [ ] Integrate Vault with Kubernetes secrets using Vault Secrets Operator (see [docs/todo/vault-to-k8s-secrets.md](docs/todo/vault-to-k8s-secrets.md))
- [ ] Consider switching from VSO to ESO if multi-backend support becomes needed (AWS Secrets Manager, GCP, etc.) - see [docs/todo/eso-vs-vso-comparison.md](docs/todo/eso-vs-vso-comparison.md)
- [ ] Install NVIDIA k8s-device-plugin for GPU-accelerated Jellyfin transcoding (see https://github.com/NVIDIA/k8s-device-plugin)
