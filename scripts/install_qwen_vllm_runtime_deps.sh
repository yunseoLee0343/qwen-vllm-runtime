#!/usr/bin/env bash
set -euo pipefail

# install_qwen_vllm_runtime_deps.sh
#
# Dependency installer for qwen-vllm-runtime on RunPod.
# Model download is intentionally excluded.
#
# Usage:
#   bash install_qwen_vllm_runtime_deps.sh
#
# Optional:
#   INSTALL_APT=0 bash install_qwen_vllm_runtime_deps.sh
#   INSTALL_VLLM=0 bash install_qwen_vllm_runtime_deps.sh
#   VLLM_VERSION=0.11.0 bash install_qwen_vllm_runtime_deps.sh

INSTALL_APT="${INSTALL_APT:-1}"
INSTALL_PYTHON_TOOLS="${INSTALL_PYTHON_TOOLS:-1}"
INSTALL_HF_TOOLS="${INSTALL_HF_TOOLS:-1}"
INSTALL_VLLM="${INSTALL_VLLM:-1}"
VLLM_VERSION="${VLLM_VERSION:-}"

PYTHON_BIN="${PYTHON_BIN:-python}"
PIP_BIN="${PIP_BIN:-python -m pip}"

log() {
  printf '\n[deps] %s\n' "$*"
}

warn() {
  printf '\n[deps:WARN] %s\n' "$*" >&2
}

run_if_root_or_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    warn "Not root and sudo not found; cannot run: $*"
    return 1
  fi
}

log "System info"
uname -a || true
nvidia-smi || warn "nvidia-smi failed or GPU not visible"
$PYTHON_BIN --version

if [ "$INSTALL_APT" = "1" ]; then
  if command -v apt-get >/dev/null 2>&1; then
    log "Installing OS packages with apt-get"
    run_if_root_or_sudo apt-get update
    run_if_root_or_sudo apt-get install -y \
      git \
      curl \
      wget \
      jq \
      ca-certificates \
      build-essential \
      pkg-config \
      python3-dev \
      tmux \
      htop \
      ncdu \
      unzip
  else
    warn "apt-get not found; skipping OS package install"
  fi
else
  log "Skipping apt packages because INSTALL_APT=$INSTALL_APT"
fi

if [ "$INSTALL_PYTHON_TOOLS" = "1" ]; then
  log "Upgrading Python packaging tools"
  $PIP_BIN install -U pip setuptools wheel packaging
else
  log "Skipping Python packaging tools"
fi

if [ "$INSTALL_HF_TOOLS" = "1" ]; then
  log "Installing Hugging Face helper tools"
  $PIP_BIN install -U "huggingface_hub[cli]" hf_transfer safetensors accelerate
else
  log "Skipping Hugging Face helper tools"
fi

if [ "$INSTALL_VLLM" = "1" ]; then
  if [ -n "$VLLM_VERSION" ]; then
    log "Installing vLLM==$VLLM_VERSION"
    $PIP_BIN install -U "vllm==${VLLM_VERSION}"
  else
    log "Installing/upgrading vLLM"
    $PIP_BIN install -U vllm
  fi
else
  log "Skipping vLLM install because INSTALL_VLLM=$INSTALL_VLLM"
fi

log "Version checks"
set +e
$PYTHON_BIN - <<'PY'
import importlib.metadata as md
pkgs = ["torch", "vllm", "transformers", "huggingface_hub", "safetensors", "accelerate"]
for p in pkgs:
    try:
        print(f"{p}=={md.version(p)}")
    except Exception as e:
        print(f"{p}: NOT INSTALLED ({e})")
PY
set -e

log "Command checks"
command -v git
command -v curl
command -v jq || true
command -v hf || command -v huggingface-cli || true
command -v vllm || true

log "vLLM import check"
$PYTHON_BIN - <<'PY'
import importlib.util
spec = importlib.util.find_spec("vllm")
if spec is None:
    raise SystemExit("vllm import check failed: module not found")
print("vllm module:", spec.origin)
PY

log "CUDA / torch check"
$PYTHON_BIN - <<'PY'
try:
    import torch
    print("torch:", torch.__version__)
    print("cuda_available:", torch.cuda.is_available())
    if torch.cuda.is_available():
        print("cuda_device_count:", torch.cuda.device_count())
        print("cuda_device_name:", torch.cuda.get_device_name(0))
except Exception as e:
    print("torch check failed:", repr(e))
PY

log "Dependency install complete"
cat <<'EOF'

Next steps:

  # 1. Bootstrap runtime repo/scripts, excluding model download.
  bash setup_qwen_vllm_runtime.sh

  # 2. After model weights exist:
  cd /workspace/qwen-vllm-runtime
  export MODEL_PATH=/workspace/models/qwen3.5
  export SERVED_MODEL_NAME=qwen3.6
  export VLLM_PORT=8000

  bash scripts/run_vllm.sh

  # 3. In another terminal:
  curl -fsS http://localhost:8000/v1/models
  bash scripts/check_chat.sh http://localhost:8000 qwen3.6

EOF
