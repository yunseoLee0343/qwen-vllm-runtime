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
