#!/usr/bin/env bash
set -euo pipefail

# setup_qwen_vllm_runtime.sh
# Bootstrap qwen-vllm-runtime on RunPod.
# Model download is intentionally excluded.

REPO_URL="${REPO_URL:-https://github.com/yunseoLee0343/qwen-vllm-runtime.git}"
WORKSPACE="${WORKSPACE:-/workspace}"
PROJECT_DIR="${PROJECT_DIR:-${WORKSPACE}/qwen-vllm-runtime}"

MODEL_PATH="${MODEL_PATH:-${WORKSPACE}/models/qwen3.5}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-qwen3.6}"
VLLM_HOST="${VLLM_HOST:-0.0.0.0}"
VLLM_PORT="${VLLM_PORT:-8000}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-8192}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.90}"
DTYPE="${DTYPE:-auto}"
TENSOR_PARALLEL_SIZE="${TENSOR_PARALLEL_SIZE:-1}"

INSTALL_VLLM="${INSTALL_VLLM:-1}"
START_VLLM="${START_VLLM:-0}"

log() { printf '\n[setup] %s\n' "$*"; }
warn() { printf '\n[setup:WARN] %s\n' "$*" >&2; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "[setup:ERROR] missing: $1" >&2; exit 1; }; }

log "Checking tools"
need_cmd bash
need_cmd git
need_cmd python

mkdir -p "$WORKSPACE"

if [ -d "$PROJECT_DIR/.git" ]; then
  log "Updating repo: $PROJECT_DIR"
  git -C "$PROJECT_DIR" pull --ff-only || warn "git pull failed; continuing"
else
  log "Cloning repo: $REPO_URL -> $PROJECT_DIR"
  rm -rf "$PROJECT_DIR"
  git clone "$REPO_URL" "$PROJECT_DIR"
fi

cd "$PROJECT_DIR"
mkdir -p scripts docs runtime

log "Writing .env.example"
cat > .env.example <<EOF
MODEL_PATH=${MODEL_PATH}
SERVED_MODEL_NAME=${SERVED_MODEL_NAME}
VLLM_HOST=${VLLM_HOST}
VLLM_PORT=${VLLM_PORT}
MAX_MODEL_LEN=${MAX_MODEL_LEN}
GPU_MEMORY_UTILIZATION=${GPU_MEMORY_UTILIZATION}
DTYPE=${DTYPE}
TENSOR_PARALLEL_SIZE=${TENSOR_PARALLEL_SIZE}
EOF

log "Writing scripts/run_vllm.sh"
cat > scripts/run_vllm.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

MODEL_PATH="${MODEL_PATH:-/workspace/models/qwen3.5}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-qwen3.6}"
VLLM_HOST="${VLLM_HOST:-0.0.0.0}"
VLLM_PORT="${VLLM_PORT:-8000}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-8192}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.90}"
DTYPE="${DTYPE:-auto}"
TENSOR_PARALLEL_SIZE="${TENSOR_PARALLEL_SIZE:-1}"

echo "[run_vllm] model=${MODEL_PATH} served-name=${SERVED_MODEL_NAME} port=${VLLM_PORT}"

if [ ! -d "${MODEL_PATH}" ]; then
  echo "[run_vllm:ERROR] MODEL_PATH does not exist: ${MODEL_PATH}" >&2
  echo "Download or mount the HF model first." >&2
  exit 2
fi

if command -v vllm >/dev/null 2>&1; then
  exec vllm serve "${MODEL_PATH}" \
    --served-model-name "${SERVED_MODEL_NAME}" \
    --host "${VLLM_HOST}" \
    --port "${VLLM_PORT}" \
    --dtype "${DTYPE}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}" \
    --tensor-parallel-size "${TENSOR_PARALLEL_SIZE}"
fi

exec python -m vllm.entrypoints.openai.api_server \
  --model "${MODEL_PATH}" \
  --served-model-name "${SERVED_MODEL_NAME}" \
  --host "${VLLM_HOST}" \
  --port "${VLLM_PORT}" \
  --dtype "${DTYPE}" \
  --max-model-len "${MAX_MODEL_LEN}" \
  --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}" \
  --tensor-parallel-size "${TENSOR_PARALLEL_SIZE}"
EOF
chmod +x scripts/run_vllm.sh

log "Writing scripts/check_models.sh"
cat > scripts/check_models.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
BASE_URL="${1:-${VLLM_BASE_URL:-http://localhost:8000}}"
BASE_URL="${BASE_URL%/}"
echo "[check_models] ${BASE_URL}/v1/models"
curl -fsS "${BASE_URL}/v1/models"
echo
EOF
chmod +x scripts/check_models.sh

log "Writing scripts/check_chat.sh"
cat > scripts/check_chat.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
BASE_URL="${1:-${VLLM_BASE_URL:-http://localhost:8000}}"
MODEL="${2:-${SERVED_MODEL_NAME:-qwen3.6}}"
BASE_URL="${BASE_URL%/}"

echo "[check_chat] ${BASE_URL}/v1/chat/completions model=${MODEL}"
curl -fsS "${BASE_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${MODEL}\",
    \"messages\": [
      {\"role\": \"system\", \"content\": \"너는 식물 관리 도우미다. 내부 추론이나 Thinking Process를 출력하지 말고 최종 답변만 짧게 한국어로 답해라.\"},
      {\"role\": \"user\", \"content\": \"몬스테라 물은 언제 줘?\"}
    ],
    \"max_tokens\": 256,
    \"temperature\": 0.0,
    \"stream\": false
  }"
echo
EOF
chmod +x scripts/check_chat.sh

log "Writing scripts/print_backend_env.sh"
cat > scripts/print_backend_env.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
BASE_URL="${1:?usage: ./scripts/print_backend_env.sh <public-base-url> [model]}"
MODEL="${2:-qwen3.6}"
cat <<ENV
LLM_BACKEND=qwen
QWEN_LLM_MODEL=${MODEL}
QWEN_LLM_BASE_URL=${BASE_URL%/}
QWEN_LLM_TIMEOUT_SECONDS=120
ENV
EOF
chmod +x scripts/print_backend_env.sh

log "Writing scripts/export_endpoint.sh"
cat > scripts/export_endpoint.sh <<'EOF'
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
echo "[export_endpoint] written to ${OUT}"
cat "${OUT}"
EOF
chmod +x scripts/export_endpoint.sh

log "Writing README.md"
cat > README.md <<'EOF'
# qwen-vllm-runtime

RunPod GPU runtime that serves Qwen through vLLM's OpenAI-compatible API.

This repo does not download model weights.

## Quick Start

```bash
cd /workspace/qwen-vllm-runtime

export MODEL_PATH=/workspace/models/qwen3.5
export SERVED_MODEL_NAME=qwen3.6
export VLLM_PORT=8000

bash scripts/run_vllm.sh
```

Expose port `8000` in RunPod, then:

```bash
export VLLM_BASE_URL=https://<runpod-8000-url>
bash scripts/check_models.sh "$VLLM_BASE_URL"
bash scripts/check_chat.sh "$VLLM_BASE_URL" qwen3.6
bash scripts/export_endpoint.sh "$VLLM_BASE_URL" qwen3.6
```
EOF

log "Writing docs"
cat > docs/RUNPOD_SETUP.md <<'EOF'
# RunPod Setup

1. Put HF model files under `/workspace/models/qwen3.5`.
2. Run:

```bash
cd /workspace/qwen-vllm-runtime
export MODEL_PATH=/workspace/models/qwen3.5
export SERVED_MODEL_NAME=qwen3.6
bash scripts/run_vllm.sh
```

3. Expose port `8000`.
4. Test:

```bash
export VLLM_BASE_URL=https://<runpod-8000-url>
bash scripts/check_models.sh "$VLLM_BASE_URL"
bash scripts/check_chat.sh "$VLLM_BASE_URL" qwen3.6
```
EOF

cat > docs/BACKEND_INTEGRATION.md <<'EOF'
# Backend Integration

Static env:

```env
LLM_BACKEND=qwen
QWEN_LLM_MODEL=qwen3.6
QWEN_LLM_BASE_URL=https://<runpod-8000-url>
QWEN_LLM_TIMEOUT_SECONDS=120
```

Generate:

```bash
bash scripts/print_backend_env.sh https://<runpod-8000-url> qwen3.6
bash scripts/export_endpoint.sh https://<runpod-8000-url> qwen3.6
```

Do not append `/v1/chat/completions` to the base URL.
EOF

cat > docs/TROUBLESHOOTING.md <<'EOF'
# Troubleshooting

## 404 from /v1/chat/completions

The request `model` does not match served model name.

Check:

```bash
curl -fsS http://localhost:8000/v1/models
```

Restart with:

```bash
export SERVED_MODEL_NAME=qwen3.6
bash scripts/run_vllm.sh
```

## Public URL fails

Expose port 8000 in RunPod dashboard.
EOF

log "Writing docker-compose.yml"
cat > docker-compose.yml <<'EOF'
services:
  qwen-vllm:
    image: vllm/vllm-openai:latest
    ipc: host
    ports:
      - "${HOST_PORT:-8000}:8000"
    volumes:
      - "${MODEL_ROOT:-/workspace/models}:/models:ro"
    command:
      - --model
      - ${MODEL_PATH:-/models/qwen3.5}
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
EOF

if [ "$INSTALL_VLLM" = "1" ]; then
  log "Installing/upgrading vLLM"
  python -m pip install -U pip
  python -m pip install -U vllm
else
  log "Skipping vLLM install"
fi

log "Syntax checking generated scripts"
bash -n scripts/run_vllm.sh
bash -n scripts/check_models.sh
bash -n scripts/check_chat.sh
bash -n scripts/print_backend_env.sh
bash -n scripts/export_endpoint.sh

if [ -d "$MODEL_PATH" ]; then
  log "Model path exists: $MODEL_PATH"
  ls -lah "$MODEL_PATH" | head -30
else
  warn "Model path missing: $MODEL_PATH"
  warn "Download/model mount is intentionally not automated by this setup script."
fi

if [ "$START_VLLM" = "1" ]; then
  log "Starting vLLM"
  export MODEL_PATH SERVED_MODEL_NAME VLLM_HOST VLLM_PORT MAX_MODEL_LEN GPU_MEMORY_UTILIZATION DTYPE TENSOR_PARALLEL_SIZE
  exec bash scripts/run_vllm.sh
fi

log "Setup complete"
cat <<EOF

Next:

  cd "$PROJECT_DIR"
  export MODEL_PATH="$MODEL_PATH"
  export SERVED_MODEL_NAME="$SERVED_MODEL_NAME"
  export VLLM_PORT="$VLLM_PORT"
  bash scripts/run_vllm.sh

Expose port $VLLM_PORT in RunPod, then:

  export VLLM_BASE_URL=https://<runpod-${VLLM_PORT}-url>
  bash scripts/check_models.sh "\$VLLM_BASE_URL"
  bash scripts/check_chat.sh "\$VLLM_BASE_URL" "$SERVED_MODEL_NAME"
  bash scripts/export_endpoint.sh "\$VLLM_BASE_URL" "$SERVED_MODEL_NAME"

EOF
