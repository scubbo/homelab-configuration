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

**1. NVIDIA driver — on Windows only.**
Install the latest GeForce driver from nvidia.com. It ships the WSL CUDA driver automatically.
**Do NOT install any NVIDIA driver *inside* WSL** — that breaks the GPU projection.

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
- **CLI:** `docker exec -it ollama ollama run qwen3:30b`

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

## Reaching it from other machines

`OLLAMA_HOST=0.0.0.0` already binds the API to all interfaces in the container. To hit it
from elsewhere on your LAN you'll need to allow the port through the Windows firewall
(WSL2 forwards `localhost`, but LAN access to `:11434`/`:3000` needs a firewall rule, and
sometimes a `netsh portproxy` entry). If you later want it behind Traefik on `.avril` with a
`DNSEndpoint` like your other services, that's a natural follow-up — say the word.

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
