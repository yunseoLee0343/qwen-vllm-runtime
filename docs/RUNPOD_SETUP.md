# RunPod Setup Guide

## Prerequisites

- RunPod account with GPU pod access
- A RunPod pod with an NVIDIA GPU (A100, A10, RTX 4090, or similar)
- vLLM pre-installed in the pod image (e.g., `runpod/pytorch` with vLLM, or `vllm/vllm-openai`)
- Qwen3.6 model weights downloaded to `/workspace/models/qwen3.6`

---

## Step 1 — Prepare Model Weights

The model must be a Hugging Face Transformers-format directory with safetensors weights.

Expected layout:

```
/workspace/models/qwen3.6/
  config.json
  generation_config.json
  tokenizer.json
  tokenizer_config.json
  special_tokens_map.json
  model-*.safetensors
```

Download example (run inside the pod terminal):

```bash
pip install -q huggingface_hub
huggingface-cli download Qwen/Qwen3-1.7B \
  --local-dir /workspace/models/qwen3.6 \
  --local-dir-use-symlinks False
```

> Replace `Qwen/Qwen3-1.7B` with the actual Qwen3.6 model repo name when it is
> publicly available.  This ticket does not automate the download.

---

## Step 2 — Clone This Repo Into the Pod

```bash
cd /workspace
git clone <this-repo-url> qwen-vllm-runtime
cd qwen-vllm-runtime
```

---

## Step 3 — Start vLLM

### Option A — bare script (recommended for RunPod)

```bash
export MODEL_PATH=/workspace/models/qwen3.6
export SERVED_MODEL_NAME=qwen3.6
export VLLM_PORT=8000
export MAX_MODEL_LEN=8192
export GPU_MEMORY_UTILIZATION=0.90
export TENSOR_PARALLEL_SIZE=1

bash scripts/run_vllm.sh
```

### Option B — Docker Compose (if Docker is available in the pod)

```bash
cp .env.example .env
# Edit .env to set MODEL_ROOT=/workspace/models and any other values
docker compose up -d
docker compose logs -f
```

> **Note on `runtime: nvidia`**: if Docker reports an unknown runtime, comment
> out the `runtime: nvidia` line in `docker-compose.yml` — RunPod pods already
> have GPU access by default.

---

## Step 4 — Expose Port on RunPod

In the RunPod dashboard for your pod:

1. Go to **Connect** → **Expose Port**
2. Add port `8000` (or whatever `VLLM_PORT` you set)
3. Copy the resulting public URL, e.g.:
   ```
   https://abc123-8000.proxy.runpod.net
   ```

---

## Step 5 — Smoke Test

```bash
# From inside the pod or from any machine with the public URL:
export VLLM_BASE_URL=https://abc123-8000.proxy.runpod.net

bash scripts/check_models.sh "$VLLM_BASE_URL"
bash scripts/check_chat.sh  "$VLLM_BASE_URL" qwen3.6
```

Expected output from `check_models.sh`:

```json
{"object":"list","data":[{"id":"qwen3.6","object":"model",...}]}
```

Expected output from `check_chat.sh`: HTTP 200 with a non-empty
`choices[0].message.content`.

---

## Step 6 — Export Endpoint for EC2 Backend

```bash
bash scripts/export_endpoint.sh https://abc123-8000.proxy.runpod.net qwen3.6
# writes qwen_endpoint.json
```

Send the JSON file to the EC2 backend operator, or push it via the TICKET-055
dynamic endpoint registry API (see `docs/BACKEND_INTEGRATION.md`).

---

## Stopping vLLM

If using the bare script:

```bash
# Ctrl-C in the terminal running run_vllm.sh, or:
pkill -f vllm
```

If using Docker Compose:

```bash
docker compose down
```
