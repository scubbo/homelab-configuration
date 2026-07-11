# alpha

Configuration for applications that run on my Gaming PC (`alpha`), which is **not** part of
the Homelab Kubernetes cluster.

Unlike the rest of this repo — ArgoCD-managed k8s apps under `app-of-apps/`, `charts/`, and
`manifests/` — the configuration here is deployed manually on a standalone machine. Copy the
relevant subdirectory to `alpha` and follow its own README.

## Contents

- [`local-llm-config/`](./local-llm-config/) — Docker Compose stack for local LLM serving
  (Ollama + Open WebUI) on the RTX 5090, via WSL2.
