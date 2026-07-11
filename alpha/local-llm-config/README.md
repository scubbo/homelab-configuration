# local-llm-config

Declarative local LLM serving for a Windows + WSL2 box with an NVIDIA GPU (targeted at an
RTX 5090, 32GB). Everything is config: edit a file, `docker compose up -d`, redeploy.

## What's in the box

| Service        | Purpose                                              | Endpoint                |
|----------------|------------------------------------------------------|-------------------------|
| `ollama`       | Inference server (native + OpenAI-compatible API)    | http://localhost:11434  |
| `model-loader` | One-shot: pulls `models.txt` + builds `modelfiles/*` | (exits after running)   |
| `open-webui`   | ChatGPT-like web UI for daily use                    | http://localhost:3000   |

```
local-llm-config/
├── docker-compose.yml        # the stack
├── env.example               # tuning knobs — copy to .env to override (context, KV cache, ...)
├── models.txt                # which models to pull  <-- edit me
├── modelfiles/
│   └── assistant.Modelfile   # example custom model (system prompt + params)
└── bootstrap/
    └── pull-models.sh         # provisioning script run by model-loader
```

## Prerequisites (Windows + WSL2)

> Versions below are from early 2026 — the RTX 5090 (Blackwell) needs a recent driver, so
> grab the current release rather than trusting a pinned number here.

**1. NVIDIA driver — on the Windows host only.**
The WSL CUDA driver ships with the Windows driver. **Never install an NVIDIA driver *inside*
WSL** — that breaks the GPU projection.

Headless over SSH (no desktop)? UAC can't display a prompt, so you need an already-elevated
shell. Windows OpenSSH usually gives an admin account a full token — confirm from PowerShell:
```powershell
whoami /groups | findstr /i "High Mandatory"    # a line here means you're elevated
```
Then install via Chocolatey (the bootstrap is one line):
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
choco upgrade nvidia-display-driver -y
```
**After any driver install/update, restart the WSL VM** so it picks up the new libraries,
or `nvidia-smi` inside WSL will segfault:
```powershell
wsl --shutdown        # from Windows; reopen WSL afterward
```
Verify with `nvidia-smi` in both PowerShell and WSL — both should list the GPU.

**2. WSL2 + Ubuntu.** In an admin PowerShell:
```powershell
wsl --install
wsl --update
wsl -l -v          # confirm your distro shows VERSION 2
```

**3. Docker Engine inside WSL Ubuntu** (cleaner and license-free vs Docker Desktop):
```bash
# Enable systemd so `systemctl` manages docker
printf '[boot]\nsystemd=true\n' | sudo tee /etc/wsl.conf
# (then run `wsl --shutdown` from PowerShell once, and reopen Ubuntu)

curl -fsSL https://get.docker.com | sh          # installs docker + compose plugin
sudo usermod -aG docker "$USER"                 # log out/in of the shell afterward
```
*(Prefer Docker Desktop? Install it, enable WSL2 integration for your distro, and its GPU
support covers the next step — then skip to step 5.)*

**4. NVIDIA Container Toolkit inside WSL Ubuntu:**
```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

**5. Smoke-test GPU passthrough:**
```bash
docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu24.04 nvidia-smi
```
You should see your 5090 listed. If not, see Troubleshooting below before continuing.

## First run

> **If this box already ran Ollama natively** (a WSL `ollama.service` or the Windows app), it
> holds port 11434 and the containerized `ollama` won't start (`bind: address already in use`).
> Disable it first — `sudo systemctl disable --now ollama` in WSL. Existing models stay on disk
> (`~/.ollama`), just not visible to the container.

From this directory, inside WSL:
```bash
cp env.example .env           # optional: only needed if you want to change the defaults
docker compose up -d          # starts ollama + open-webui, and runs model-loader once
docker compose logs -f model-loader   # watch the model(s) download
```
First launch pulls the default model (`qwen3:30b`, ~18-20GB) — give it time. When the
loader exits cleanly, open **http://localhost:3000**, create your admin account, pick the
model, and chat.

## Daily use

- **Web UI:** http://localhost:3000
- **API (OpenAI-compatible):** point any tool at `http://localhost:11434/v1` (dummy API key):
  ```bash
  curl http://localhost:11434/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"qwen3:30b","messages":[{"role":"user","content":"hello"}]}'
  ```
- **CLI:** `docker compose exec ollama ollama run qwen3:30b`

## Tweak & redeploy

| To change...                    | Edit...                     | Then run...                          |
|---------------------------------|-----------------------------|--------------------------------------|
| Which models exist              | `models.txt`                | `docker compose up model-loader`     |
| A custom model's prompt/params  | `modelfiles/*.Modelfile`    | `docker compose up model-loader`     |
| Context size, KV cache, etc.    | `.env` (from `env.example`) | `docker compose up -d`               |
| Update to newer images          | —                           | `docker compose pull && docker compose up -d` |

## VRAM tips (32GB budget)

- **Stay ≤ ~35B.** Well-quantized sub-35B / MoE models beat a mangled 70B at Q2 every time.
- **KV cache is not free.** `OLLAMA_CONTEXT_LENGTH` × model = memory. The defaults
  (32k context, flash attention on, `q8_0` KV cache) keep it comfortable. Raise context
  deliberately, not by reflex.
- **`OLLAMA_MAX_LOADED_MODELS=2`** lets a chat model and a coding model stay hot together —
  fine for two sub-30B MoE models, watch `nvidia-smi` to confirm you fit.
- **`OLLAMA_KEEP_ALIVE`** trades responsiveness vs. freeing VRAM for other apps/games.

## Reaching it on the LAN (`alpha.avril`)

Two pieces make the UI reachable at `http://alpha.avril:3000` from any device:

1. **DNS** — `alpha.avril` → this box's LAN IP, via `charts/external-dns/alpha-dns-endpoint.yaml`
   (the cluster's external-dns writes it into OPNsense). Cluster-managed, so it deploys through
   ArgoCD like the other `.avril` records.
2. **Host → container** — Docker publishes `:3000` inside the WSL2 VM, which Windows only
   forwards from *localhost*. To reach it from the LAN, run `expose-openwebui.ps1` from an
   **elevated** PowerShell on the Windows host:
   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\expose-openwebui.ps1
   ```
   It re-derives WSL's current IP, sets a `netsh` portproxy (`LAN:3000` → container), and
   ensures an inbound firewall rule.

   **Access is LAN-only.** The proxy binds to this host's LAN IP (not other interfaces like
   Tailscale), and the firewall rule admits only sources on the local subnet (`-LanCidr`,
   default `192.168.1.0/24` — pass your own if it differs). The public internet can't reach
   it regardless: the script touches only the host, never the router, so no port is forwarded.

> **Windows 10 caveat:** mirrored WSL networking — which would make this automatic — needs
> Windows 11 22H2+. On Windows 10 the WSL NAT IP can change across reboots, so if the UI stops
> responding from the LAN after a reboot, just re-run `expose-openwebui.ps1`; it re-points the
> proxy at the current IP. (Want it fully hands-off? A boot-time scheduled task can re-run it
> for you — ask and we'll add one.)

## Upgrade path

If daily use outgrows Ollama (you want max throughput, batching, or to serve many agents at
once), the same `.env`/compose shape ports to **vLLM** — swap the image, mount a HuggingFace
cache, and keep the OpenAI-compatible API so nothing downstream changes.

## Troubleshooting

- **`nvidia-smi` works on Windows but not in the container:** re-run
  `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`.
  Confirm you did NOT install a Linux NVIDIA driver inside WSL.
- **`model-loader` exits with an error creating a custom model:** its `FROM` must reference a
  model that's in `models.txt`. Pulls run before builds, so the pulls still succeeded.
- **UI can't reach models:** check `docker compose logs ollama` and that the healthcheck is
  green (`docker compose ps`).
- **A model tag 404s:** the tag moved — check https://ollama.com/library for the current name.
- **`nvidia-smi` segfaults in WSL but works in Windows PowerShell:** the WSL VM is holding a
  stale driver after an install/update. Run `wsl --shutdown` from Windows, then reopen WSL.
- **`bind: address already in use` on `:11434` or `:3000`:** another process owns the port —
  commonly a native Ollama. `sudo systemctl disable --now ollama` (or stop the Windows Ollama
  app), then `docker compose up -d`.
