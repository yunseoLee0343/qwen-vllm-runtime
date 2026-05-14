# qwen-vllm-runtime

RunPod GPU runtime that serves **Qwen3.6** via vLLM's OpenAI-compatible API.

`sunshine_backend` connects to this runtime through `QWEN_LLM_BASE_URL`.

---

## Quick Start (RunPod)

```bash
# 1. Download Qwen3.6 weights into the pod
mkdir -p /workspace/models/qwen3.6
# <copy or huggingface-cli download weights here>

# 2. Clone this repo
cd /workspace && git clone <this-repo-url> qwen-vllm-runtime && cd qwen-vllm-runtime

# 3. Start vLLM
export MODEL_PATH=/workspace/models/qwen3.6
export SERVED_MODEL_NAME=qwen3.6
export VLLM_PORT=8000
bash scripts/run_vllm.sh

# 4. Expose port 8000 in the RunPod dashboard, then smoke-test
export VLLM_BASE_URL=https://abc123-8000.proxy.runpod.net
bash scripts/check_models.sh "$VLLM_BASE_URL"
bash scripts/check_chat.sh   "$VLLM_BASE_URL" qwen3.6

# 5. Export endpoint for sunshine_backend
bash scripts/export_endpoint.sh "$VLLM_BASE_URL" qwen3.6
```

See `docs/RUNPOD_SETUP.md` for the full setup walkthrough.

---

## Endpoint Contract

| Endpoint | Method |
|---|---|
| `/v1/models` | GET |
| `/v1/chat/completions` | POST |

The model name exposed to clients is `qwen3.6`.

---

## Backend Environment Variables

```env
LLM_BACKEND=qwen
QWEN_LLM_MODEL=qwen3.6
QWEN_LLM_BASE_URL=https://<runpod-host>:<port>
QWEN_LLM_TIMEOUT_SECONDS=120
```

Generate with:

```bash
bash scripts/print_backend_env.sh https://<runpod-host>:<port>
```

---

## File Layout

```
.env.example
docker-compose.yml
scripts/
  run_vllm.sh          — start vLLM server
  check_models.sh      — smoke-test GET /v1/models
  check_chat.sh        — smoke-test POST /v1/chat/completions
  print_backend_env.sh — emit env vars for sunshine_backend
  export_endpoint.sh   — emit TICKET-055 registry JSON
docs/
  RUNPOD_SETUP.md
  BACKEND_INTEGRATION.md
  TROUBLESHOOTING.md
```

---

## Docs

- [RunPod Setup](docs/RUNPOD_SETUP.md)
- [Backend Integration](docs/BACKEND_INTEGRATION.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

---

## Scope

This repo owns GPU/model-serving only.  It does not touch `sunshine_backend`,
the embedding model, ONNX Runtime, RAG, PromptBuilder, or any frontend code.
