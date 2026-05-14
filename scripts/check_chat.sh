#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-${VLLM_BASE_URL:-http://localhost:8000}}"
MODEL="${2:-${SERVED_MODEL_NAME:-qwen3.6}}"

echo "[check_chat] POST ${BASE_URL%/}/v1/chat/completions model=${MODEL}"
curl -fsS "${BASE_URL%/}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "{
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
