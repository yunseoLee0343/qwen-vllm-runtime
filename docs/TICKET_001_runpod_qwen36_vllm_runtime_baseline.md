# TICKET-001 — Remote Qwen3.6 vLLM Runtime Baseline

## 0. Project Identity

### Project Name

```text
qwen-vllm-runtime
```

### Ticket ID

```text
TICKET-001
```

### Name

```text
RunPod Qwen3.6 vLLM Runtime Baseline
```

### Goal

Create a standalone runtime project that runs Qwen3.6 on a RunPod GPU with vLLM and exposes an OpenAI-compatible HTTP endpoint consumable by `sunshine_backend`.

This project owns the GPU/model-serving side only.

```text
HF Qwen3.6 model path
  -> vLLM OpenAI-compatible server
  -> public or protected endpoint
  -> /v1/models
  -> /v1/chat/completions
```

`sunshine_backend` will call this service through `QWEN_LLM_BASE_URL` or the later dynamic endpoint registry.

---

## 1. Scope

TICKET-001 owns:

```text
- standalone repository skeleton
- Dockerfile or RunPod launch script for vLLM
- model path configuration
- Qwen3.6 served-model-name contract
- OpenAI-compatible endpoint smoke tests
- runtime health script
- endpoint export file for EC2 backend
- minimal operational docs
```

TICKET-001 does not own:

```text
- sunshine_backend code changes
- PromptBuilder
- EvidenceBuilder
- RAG
- embedding model
- Qwen/Qwen3-Embedding-0.6B
- ONNX Runtime
- local tokenizer generation loop in FastAPI
- frontend UI
- sensor/MQTT pipeline
```

---

## 2. Runtime Contract

### Required runtime

The runtime must expose an OpenAI-compatible vLLM API.

Required endpoints:

```http
GET /v1/models
POST /v1/chat/completions
```

Required model name exposed to clients:

```text
qwen3.6
```

Required serving semantics:

```text
- non-streaming chat completion works
- system + user messages work
- max_tokens is respected
- temperature is accepted
- response contains choices[0].message.content
- response optionally contains usage.prompt_tokens and usage.completion_tokens
```

### Required public contract

The endpoint must be usable by the backend as:

```env
LLM_BACKEND=qwen
QWEN_LLM_MODEL=qwen3.6
QWEN_LLM_BASE_URL=http://<runpod-host>:<runpod-port>
QWEN_LLM_TIMEOUT_SECONDS=120
```

`QWEN_LLM_BASE_URL` must not include `/v1/chat/completions`.

Correct:

```text
http://<runpod-host>:<port>
```

Incorrect:

```text
http://<runpod-host>:<port/v1/chat/completions
```

---

## 3. Recommended Repository Layout

Create a new repo such as:

```text
qwen-vllm-runtime/
```

Recommended files:

```text
README.md
.env.example
docker-compose.yml
Dockerfile                 # optional if using official vLLM image directly
scripts/
  run_vllm.sh
  check_models.sh
  check_chat.sh
  export_endpoint.sh
  print_backend_env.sh
docs/
  RUNPOD_SETUP.md
  BACKEND_INTEGRATION.md
  TROUBLESHOOTING.md
```

---

## 4. Environment Contract

`.env.example`:

```env
# Model
MODEL_PATH=/models/qwen3.6
SERVED_MODEL_NAME=qwen3.6

# vLLM server
VLLM_HOST=0.0.0.0
VLLM_PORT=8000

# Runtime tuning
GPU_MEMORY_UTILIZATION=0.90
MAX_MODEL_LEN=8192
DTYPE=auto
TENSOR_PARALLEL_SIZE=1

# Optional auth/proxy layer, not directly supported by bare vLLM
API_KEY=
```

Rules:

```text
- MODEL_PATH must point to a Hugging Face Transformers-format model directory.
- SERVED_MODEL_NAME must equal qwen3.6 unless sunshine_backend config is changed.
- VLLM_PORT must be the internal container port.
- RunPod external mapped port may differ from VLLM_PORT.
```

---

## 5. Model Artifact Contract

Expected Hugging Face model directory:

```text
/models/qwen3.6/
  config.json
  generation_config.json
  tokenizer.json
  tokenizer_config.json
  special_tokens_map.json
  model-*.safetensors
```

Allowed:

```text
- HF Transformers model directory
- safetensors weights
- local mounted model path
- pre-downloaded model cache
```

Forbidden in this ticket:

```text
- ONNX-only model artifact
- TensorRT-LLM engine build
- custom tokenizer/generation loop
- model download inside backend
- embedding model download
```

---

## 6. Docker Compose Baseline

`docker-compose.yml`:

```yaml
services:
  qwen-vllm:
    image: vllm/vllm-openai:latest
    runtime: nvidia
    ipc: host
    ports:
      - "${HOST_PORT:-8000}:8000"
    volumes:
      - "${MODEL_ROOT:-/workspace/models}:/models:ro"
    environment:
      HF_HOME: /models/.cache
    command:
      - --model
      - ${MODEL_PATH:-/models/qwen3.6}
      - --served-model-name
      - ${SERVED_MODEL_NAME:-qwen3.6}
      - --host
      - 0.0.0.0
      - --port
      - "8000"
      - --dtype
      - ${DTYPE:-auto}
      - --max-model-len
      - "${MAX_MODEL_LEN:-8192}"
      - --gpu-memory-utilization
      - "${GPU_MEMORY_UTILIZATION:-0.90}"
      - --tensor-parallel-size
      - "${TENSOR_PARALLEL_SIZE:-1}"
```

If RunPod image already includes vLLM and GPU runtime, `runtime: nvidia` may be unnecessary or unsupported. Keep it documented as environment-dependent.

---

## 7. Run Script

`scripts/run_vllm.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

MODEL_PATH="${MODEL_PATH:-/models/qwen3.6}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-qwen3.6}"
VLLM_HOST="${VLLM_HOST:-0.0.0.0}"
VLLM_PORT="${VLLM_PORT:-8000}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-8192}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.90}"
DTYPE="${DTYPE:-auto}"
TENSOR_PARALLEL_SIZE="${TENSOR_PARALLEL_SIZE:-1}"

python -m vllm.entrypoints.openai.api_server   --model "${MODEL_PATH}"   --served-model-name "${SERVED_MODEL_NAME}"   --host "${VLLM_HOST}"   --port "${VLLM_PORT}"   --dtype "${DTYPE}"   --max-model-len "${MAX_MODEL_LEN}"   --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}"   --tensor-parallel-size "${TENSOR_PARALLEL_SIZE}"
```

Alternative if `vllm serve` is available:

```bash
vllm serve "${MODEL_PATH}"   --served-model-name "${SERVED_MODEL_NAME}"   --host "${VLLM_HOST}"   --port "${VLLM_PORT}"   --dtype "${DTYPE}"   --max-model-len "${MAX_MODEL_LEN}"   --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}"   --tensor-parallel-size "${TENSOR_PARALLEL_SIZE}"
```

---

## 8. Health Scripts

### `scripts/check_models.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-${VLLM_BASE_URL:-http://localhost:8000}}"

curl -fsS "${BASE_URL%/}/v1/models"
echo
```

### `scripts/check_chat.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-${VLLM_BASE_URL:-http://localhost:8000}}"
MODEL="${2:-${SERVED_MODEL_NAME:-qwen3.6}}"

curl -fsS "${BASE_URL%/}/v1/chat/completions"   -H "Content-Type: application/json"   -d "{
    \"model\": \"${MODEL}\",
    \"messages\": [
      {\"role\": \"system\", \"content\": \"너는 식물 관리 도우미다. 답변은 짧게 해라.\"},
      {\"role\": \"user\", \"content\": \"몬스테라 물은 언제 줘?\"}
    ],
    \"max_tokens\": 128,
    \"temperature\": 0.0,
    \"stream\": false
  }"
echo
```

### `scripts/print_backend_env.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:?usage: ./scripts/print_backend_env.sh <public-base-url>}"
MODEL="${2:-qwen3.6}"

cat <<ENV
LLM_BACKEND=qwen
QWEN_LLM_MODEL=${MODEL}
QWEN_LLM_BASE_URL=${BASE_URL%/}
QWEN_LLM_TIMEOUT_SECONDS=120
ENV
```

### `scripts/export_endpoint.sh`

For TICKET-055 dynamic endpoint registry integration:

```bash
#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:?usage: ./scripts/export_endpoint.sh <public-base-url> [model]}"
MODEL="${2:-qwen3.6}"
OUT="${OUT:-qwen_endpoint.json}"

cat > "${OUT}" <<JSON
{
  "provider": "qwen",
  "model": "${MODEL}",
  "base_url": "${BASE_URL%/}",
  "api_key": null,
  "timeout_seconds": 120,
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
JSON

cat "${OUT}"
```

---

## 9. RunPod Setup Procedure

### Step 1. Prepare model path

Expected RunPod path:

```text
/workspace/models/qwen3.6
```

Example:

```bash
mkdir -p /workspace/models
# User downloads Qwen3.6 HF model snapshot into:
# /workspace/models/qwen3.6
```

This ticket does not download the model automatically.

### Step 2. Start vLLM

```bash
export MODEL_PATH=/workspace/models/qwen3.6
export SERVED_MODEL_NAME=qwen3.6
export VLLM_PORT=8000
export MAX_MODEL_LEN=8192
export GPU_MEMORY_UTILIZATION=0.90

bash scripts/run_vllm.sh
```

### Step 3. Expose RunPod port

Expose internal port:

```text
8000
```

Record the public RunPod URL or host:port.

Example:

```text
https://abc123-8000.proxy.runpod.net
```

or:

```text
http://<runpod-ip>:<external-port>
```

### Step 4. Smoke test

```bash
bash scripts/check_models.sh https://abc123-8000.proxy.runpod.net
bash scripts/check_chat.sh https://abc123-8000.proxy.runpod.net qwen3.6
```

### Step 5. Export endpoint for EC2 backend

```bash
bash scripts/export_endpoint.sh https://abc123-8000.proxy.runpod.net qwen3.6
```

Then send `qwen_endpoint.json` to the EC2 backend registry path or update via TICKET-055 API.

---

## 10. Backend Integration Contract

The remote runtime project must produce one of these.

### Static env output

```env
LLM_BACKEND=qwen
QWEN_LLM_MODEL=qwen3.6
QWEN_LLM_BASE_URL=https://abc123-8000.proxy.runpod.net
QWEN_LLM_TIMEOUT_SECONDS=120
```

### Dynamic registry JSON

```json
{
  "provider": "qwen",
  "model": "qwen3.6",
  "base_url": "https://abc123-8000.proxy.runpod.net",
  "api_key": null,
  "timeout_seconds": 120,
  "updated_at": "2026-05-14T12:00:00Z"
}
```

### Dynamic registry API update

```bash
curl -X PUT http://54.206.46.42:8000/internal/runtime-endpoints/qwen   -H "Content-Type: application/json"   -H "X-Internal-Token: ${INTERNAL_TOKEN}"   -d '{
    "provider": "qwen",
    "model": "qwen3.6",
    "base_url": "https://abc123-8000.proxy.runpod.net"
  }'
```

---

## 11. Security Contract

Bare vLLM OpenAI server should not be treated as public production API.

Minimum acceptable MVP options:

```text
Option A:
  RunPod endpoint is used only during dev/demo.

Option B:
  RunPod firewall or proxy allows EC2 backend IP only.

Option C:
  Put a small reverse proxy in front of vLLM that checks Authorization header.

Option D:
  Use TICKET-055 QWEN_LLM_API_KEY support from backend to protected proxy.
```

Forbidden:

```text
- publishing a long-lived unauthenticated vLLM endpoint as production
- storing raw API key in git
- logging full prompts/responses with secrets
```

---

## 12. Tests

### Runtime smoke tests

Required commands:

```bash
bash scripts/check_models.sh "$VLLM_BASE_URL"
bash scripts/check_chat.sh "$VLLM_BASE_URL" qwen3.6
```

### Expected `/v1/models`

Must return at least one model entry whose id or name is:

```text
qwen3.6
```

### Expected `/v1/chat/completions`

Must return:

```text
HTTP 200
choices[0].message.content non-empty
```

### Negative tests

- wrong model name returns non-200 or clear provider error.
- missing model path fails at startup.
- invalid public endpoint fails `check_models.sh`.
- timeout is visible to caller.

---

## 13. Functional Gate

Run from the runtime repo:

```bash
set -euo pipefail

export VLLM_BASE_URL="${VLLM_BASE_URL:?set VLLM_BASE_URL first}"

bash scripts/check_models.sh "$VLLM_BASE_URL"
bash scripts/check_chat.sh "$VLLM_BASE_URL" qwen3.6

python - <<'PY'
import json
import os
import subprocess

base = os.environ["VLLM_BASE_URL"].rstrip("/")
payload = {
    "model": "qwen3.6",
    "messages": [
        {"role": "system", "content": "너는 식물 관리 도우미다."},
        {"role": "user", "content": "몬스테라 물은 언제 줘?"}
    ],
    "max_tokens": 64,
    "temperature": 0.0,
    "stream": False,
}
cmd = [
    "curl", "-fsS", f"{base}/v1/chat/completions",
    "-H", "Content-Type: application/json",
    "-d", json.dumps(payload, ensure_ascii=False),
]
out = subprocess.check_output(cmd)
data = json.loads(out)
content = data["choices"][0]["message"]["content"]
assert content.strip(), data
print("PASS: qwen3.6 vLLM runtime responded")
PY
```

---

## 14. Acceptance Criteria

TICKET-001 is complete when all are true:

```text
- New runtime repo has README, scripts, and docs.
- vLLM can serve local HF Qwen3.6 model path.
- `/v1/models` returns successfully.
- `/v1/chat/completions` returns non-empty answer for model `qwen3.6`.
- `scripts/export_endpoint.sh` emits registry JSON compatible with TICKET-055.
- `scripts/print_backend_env.sh` emits backend env values.
- RunPod setup doc explains how to expose port and copy endpoint.
- No ONNX adapter is implemented.
- No sunshine_backend code is modified from this repo.
```

---

## 15. Do Not Implement

```text
- model download automation
- ONNX Runtime
- TensorRT-LLM
- custom generation loop
- tokenizer code
- embedding model serving
- Qwen/Qwen3-Embedding-0.6B
- frontend UI
- sensor/MQTT code
- Postgres
- RAG
- PromptBuilder
- EvidenceBuilder
- dynamic endpoint registry inside sunshine_backend
- RunPod lifecycle API control
```
