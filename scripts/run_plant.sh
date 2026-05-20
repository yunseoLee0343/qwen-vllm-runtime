#!/usr/bin/env bash
set -euo pipefail

PLANT_MODEL_PATH="${PLANT_MODEL_PATH:-/workspace/models/convnext-base-plant-121}"
PLANT_MODEL_NAME="${PLANT_MODEL_NAME:-convnext-base-plant-121}"
PLANT_HOST="${PLANT_HOST:-0.0.0.0}"
PLANT_PORT="${PLANT_PORT:-8001}"
PLANT_TOP_K="${PLANT_TOP_K:-5}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

export PLANT_MODEL_PATH
export PLANT_MODEL_NAME
export PLANT_TOP_K

echo "[run_plant] model=${PLANT_MODEL_PATH} name=${PLANT_MODEL_NAME} host=${PLANT_HOST} port=${PLANT_PORT}"

exec python3 -m uvicorn server.plant_server:app \
  --app-dir "${RUNTIME_DIR}" \
  --host "${PLANT_HOST}" \
  --port "${PLANT_PORT}"
