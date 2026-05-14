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
