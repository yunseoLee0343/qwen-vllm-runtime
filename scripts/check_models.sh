#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-${VLLM_BASE_URL:-http://localhost:8000}}"

echo "[check_models] GET ${BASE_URL%/}/v1/models"
curl -fsS "${BASE_URL%/}/v1/models"
echo
