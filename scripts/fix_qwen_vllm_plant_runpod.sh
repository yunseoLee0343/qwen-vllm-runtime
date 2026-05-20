#!/usr/bin/env bash
set -euo pipefail

cd /workspace

QWEN_MODEL_DIR="${QWEN_MODEL_DIR:-/workspace/models/qwen3.5}"
PLANT_MODEL_DIR="${PLANT_MODEL_DIR:-/workspace/models/convnext-base-plant-121}"
RUNTIME_DIR="${RUNTIME_DIR:-/workspace/qwen-vllm-runtime}"

QWEN_PORT="${QWEN_PORT:-8000}"
PLANT_PORT="${PLANT_PORT:-8001}"

echo "[0] Show current state"
python3 - <<'PY' || true
import importlib.metadata as md
for p in [
    "torch", "triton", "vllm", "transformers", "tokenizers",
    "huggingface_hub", "hf_transfer", "safetensors", "numpy",
    "numba", "setuptools", "distro", "fastapi", "uvicorn",
    "pillow", "timm", "python-multipart"
]:
    try:
        print(p, md.version(p))
    except Exception as e:
        print(p, "MISSING", e)
try:
    import torch
    print("torch cuda:", torch.version.cuda)
    print("cuda available:", torch.cuda.is_available())
    if torch.cuda.is_available():
        print("gpu:", torch.cuda.get_device_name(0))
except Exception as e:
    print("torch import failed:", repr(e))
PY

echo
echo "[1] Ensure pip basics without uninstall"
python3 -m ensurepip --upgrade || true
python3 -m pip install --no-cache-dir --ignore-installed \
  "pip" \
  "wheel" \
  "packaging" \
  "setuptools>=77.0.3,<80"

echo
echo "[2] Overlay install Debian-owned package that caused uninstall failure"
python3 -m pip install --no-cache-dir --ignore-installed "distro==1.9.0"

echo
echo "[3] Overlay install serving stack; do not uninstall existing packages"
cat > /tmp/vllm_constraints.txt <<'CONSTRAINTS'
torch==2.8.0
triton==3.4.0
setuptools>=77.0.3,<80
numpy>=1.25,<2.3
CONSTRAINTS

cat /tmp/vllm_constraints.txt

python3 -m pip install --no-cache-dir --ignore-installed \
  "numpy==2.2.6" \
  "transformers==4.57.1" \
  "tokenizers==0.22.1" \
  "huggingface_hub==0.36.0" \
  "hf_transfer==0.1.9" \
  "safetensors>=0.5.0" \
  "vllm==0.11.0" \
  "fastapi>=0.115.0" \
  "uvicorn[standard]>=0.30.0" \
  "python-multipart>=0.0.9" \
  "pillow>=10.0.0" \
  "timm>=1.0.0" \
  -c /tmp/vllm_constraints.txt

echo
echo "[4] Verify imports"
python3 - <<'PY'
import torch
import numpy as np
import numba
import importlib.metadata as md

for p in [
    "torch", "triton", "vllm", "transformers", "tokenizers",
    "huggingface_hub", "hf_transfer", "safetensors", "numpy",
    "numba", "setuptools", "distro", "fastapi", "uvicorn",
    "pillow", "timm", "python-multipart"
]:
    try:
        print(f"{p}: {md.version(p)}")
    except Exception as e:
        print(f"{p}: MISSING ({e})")

print("torch cuda:", torch.version.cuda)
print("cuda available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("gpu:", torch.cuda.get_device_name(0))
print("numpy import:", np.__version__)
print("numba import:", numba.__version__)
PY

echo
echo "[5] Clone/update runtime repo"
if [ ! -d "${RUNTIME_DIR}" ]; then
  git clone https://github.com/yunseoLee0343/qwen-vllm-runtime.git "${RUNTIME_DIR}"
else
  cd "${RUNTIME_DIR}"
  git pull origin main || true
fi

mkdir -p "${RUNTIME_DIR}/scripts"
mkdir -p "${RUNTIME_DIR}/server"
mkdir -p /workspace/models
mkdir -p /workspace/logs

cd /workspace

echo
echo "[6] Download Qwen model"
mkdir -p "${QWEN_MODEL_DIR}"
export HF_HUB_ENABLE_HF_TRANSFER=1
export HF_HOME=/workspace/.cache/huggingface

if hf repo info Qwen/Qwen3-4B-Instruct >/tmp/qwen_repo_info.txt 2>&1; then
  MODEL_REPO="Qwen/Qwen3-4B-Instruct"
else
  MODEL_REPO="Qwen/Qwen3-4B"
fi

echo "[download] MODEL_REPO=${MODEL_REPO}"
rm -rf "${QWEN_MODEL_DIR:?}"/*
hf download "${MODEL_REPO}" \
  --local-dir "${QWEN_MODEL_DIR}" \
  --max-workers 8

echo
echo "[7] Download Plant ConvNeXt model"
mkdir -p "${PLANT_MODEL_DIR}"

if hf repo info dkrak737/convnext-base-plant-121 >/tmp/plant_repo_info.txt 2>&1; then
  PLANT_MODEL_REPO="dkrak737/convnext-base-plant-121"
else
  echo "[warn] dkrak737/convnext-base-plant-121 not found or inaccessible; fallback to dkrak737/sunshine-plants-convnext-384"
  PLANT_MODEL_REPO="dkrak737/sunshine-plants-convnext-384"
fi

echo "[download] PLANT_MODEL_REPO=${PLANT_MODEL_REPO}"
rm -rf "${PLANT_MODEL_DIR:?}"/*
hf download "${PLANT_MODEL_REPO}" \
  --local-dir "${PLANT_MODEL_DIR}" \
  --max-workers 8

echo
echo "[8] Verify Qwen model/tokenizer"
python3 - <<PY
import json
from pathlib import Path
from transformers import AutoTokenizer

model_dir = Path("${QWEN_MODEL_DIR}")
cfg = json.loads((model_dir / "config.json").read_text())
print("architectures:", cfg.get("architectures"))
print("model_type:", cfg.get("model_type"))

tok = AutoTokenizer.from_pretrained(str(model_dir), trust_remote_code=True)
print("tokenizer:", type(tok))
print("has all_special_tokens_extended:", hasattr(tok, "all_special_tokens_extended"))
print("special tokens:", tok.all_special_tokens[:10])
PY

echo
echo "[9] Verify Plant model files"
python3 - <<PY
import json
from pathlib import Path

model_dir = Path("${PLANT_MODEL_DIR}")
print("plant_model_dir:", model_dir)
print("files:", sorted([p.name for p in model_dir.iterdir()])[:50])

labels_path = model_dir / "labels.json"
weights_path = model_dir / "model.safetensors"

if not labels_path.exists():
    raise FileNotFoundError(f"missing labels.json: {labels_path}")
if not weights_path.exists():
    raise FileNotFoundError(f"missing model.safetensors: {weights_path}")

labels = json.loads(labels_path.read_text())
print("num_classes:", labels.get("num_classes"))
print("id2label sample:", list(labels.get("id2label", {}).items())[:5])
PY

echo
echo "[10] Write runtime env"
cat > "${RUNTIME_DIR}/.env.runtime" <<RUNTIME_ENV
# Qwen vLLM
export MODEL_PATH=${QWEN_MODEL_DIR}
export SERVED_MODEL_NAME=qwen3.6
export VLLM_HOST=0.0.0.0
export VLLM_PORT=${QWEN_PORT}
export MAX_MODEL_LEN=8192
export GPU_MEMORY_UTILIZATION=0.90
export TENSOR_PARALLEL_SIZE=1
export DTYPE=auto

# Plant ConvNeXt FastAPI
export PLANT_MODEL_PATH=${PLANT_MODEL_DIR}
export PLANT_MODEL_NAME=convnext-base-plant-121
export PLANT_HOST=0.0.0.0
export PLANT_PORT=${PLANT_PORT}
export PLANT_TOP_K=5
RUNTIME_ENV

cat "${RUNTIME_DIR}/.env.runtime"

echo
echo "[11] Write run_vllm.sh"
cat > "${RUNTIME_DIR}/scripts/run_vllm.sh" <<'RUN_VLLM'
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

echo "[run_vllm] model=${MODEL_PATH} served-name=${SERVED_MODEL_NAME} host=${VLLM_HOST} port=${VLLM_PORT}"

# Prefer `vllm serve` if available; fall back to module entrypoint.
if command -v vllm &>/dev/null; then
  exec vllm serve "${MODEL_PATH}" \
    --served-model-name "${SERVED_MODEL_NAME}" \
    --host "${VLLM_HOST}" \
    --port "${VLLM_PORT}" \
    --dtype "${DTYPE}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}" \
    --tensor-parallel-size "${TENSOR_PARALLEL_SIZE}"
else
  exec python -m vllm.entrypoints.openai.api_server \
    --model "${MODEL_PATH}" \
    --served-model-name "${SERVED_MODEL_NAME}" \
    --host "${VLLM_HOST}" \
    --port "${VLLM_PORT}" \
    --dtype "${DTYPE}" \
    --max-model-len "${MAX_MODEL_LEN}" \
    --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}" \
    --tensor-parallel-size "${TENSOR_PARALLEL_SIZE}"
fi
RUN_VLLM
chmod +x "${RUNTIME_DIR}/scripts/run_vllm.sh"

echo
echo "[12] Write plant_server.py"
cat > "${RUNTIME_DIR}/server/plant_server.py" <<'PLANT_SERVER'
#!/usr/bin/env python3
import io
import json
import os
from pathlib import Path
from typing import Any

import torch
import timm
from fastapi import FastAPI, File, UploadFile
from PIL import Image
from safetensors.torch import load_file
from timm.data import create_transform, resolve_model_data_config

MODEL_PATH = Path(os.environ.get("PLANT_MODEL_PATH", "/workspace/models/convnext-base-plant-121"))
MODEL_NAME = os.environ.get("PLANT_MODEL_NAME", "convnext-base-plant-121")
TOP_K = int(os.environ.get("PLANT_TOP_K", "5"))

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

app = FastAPI(title="Plant ConvNeXt Classifier", version="1.0.0")

model: torch.nn.Module | None = None
transform: Any = None
class_names: list[str] = []


def _load_labels(model_path: Path) -> list[str]:
    labels_path = model_path / "labels.json"
    with labels_path.open("r", encoding="utf-8") as f:
        labels = json.load(f)

    id2label = labels.get("id2label")
    if not isinstance(id2label, dict):
        raise ValueError("labels.json must contain id2label")

    return [id2label[str(i)] for i in range(len(id2label))]


@app.on_event("startup")
def startup() -> None:
    global model, transform, class_names

    if not MODEL_PATH.exists():
        raise FileNotFoundError(f"PLANT_MODEL_PATH does not exist: {MODEL_PATH}")

    weights_path = MODEL_PATH / "model.safetensors"
    if not weights_path.exists():
        raise FileNotFoundError(f"Missing model.safetensors: {weights_path}")

    class_names = _load_labels(MODEL_PATH)

    loaded = timm.create_model(
        "convnext_base.fb_in22k_ft_in1k",
        pretrained=False,
        num_classes=len(class_names),
    )
    state_dict = load_file(str(weights_path), device="cpu")
    loaded.load_state_dict(state_dict)
    loaded.eval()
    loaded.to(DEVICE)

    cfg = resolve_model_data_config(loaded)
    cfg["input_size"] = (3, 384, 384)
    transform = create_transform(**cfg, is_training=False)

    model = loaded
    print(
        f"[plant_server] loaded model={MODEL_NAME} path={MODEL_PATH} "
        f"classes={len(class_names)} device={DEVICE}"
    )


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "model": MODEL_NAME,
        "model_path": str(MODEL_PATH),
        "num_classes": len(class_names),
        "device": DEVICE,
    }


@app.get("/")
def root() -> dict[str, Any]:
    return {
        "service": "plant-convnext",
        "health": "/health",
        "predict": "POST /predict multipart/form-data field=image",
    }


@app.post("/predict")
async def predict(image: UploadFile = File(...), top_k: int | None = None) -> dict[str, Any]:
    if model is None or transform is None:
        raise RuntimeError("model is not loaded")

    k = top_k or TOP_K
    k = max(1, min(k, len(class_names)))

    raw = await image.read()
    img = Image.open(io.BytesIO(raw)).convert("RGB")
    tensor = transform(img).unsqueeze(0).to(DEVICE)

    with torch.inference_mode():
        logits = model(tensor)
        probs = logits.softmax(dim=-1)[0]
        values, indices = probs.topk(k)

    predictions = []
    for score, idx in zip(values.detach().cpu().tolist(), indices.detach().cpu().tolist()):
        predictions.append(
            {
                "label": class_names[idx],
                "score": float(score),
                "score_pct": float(score) * 100.0,
                "class_id": int(idx),
            }
        )

    return {
        "filename": image.filename,
        "model": MODEL_NAME,
        "top_k": k,
        "predictions": predictions,
    }
PLANT_SERVER

echo
echo "[13] Write run_plant.sh"
cat > "${RUNTIME_DIR}/scripts/run_plant.sh" <<'RUN_PLANT'
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
RUN_PLANT
chmod +x "${RUNTIME_DIR}/scripts/run_plant.sh"

echo
echo "[14] Kill old servers"
pkill -f "vllm" || true
pkill -f "server.plant_server:app" || true
sleep 2

echo
echo "[15] Port binding check command"
cat > "${RUNTIME_DIR}/scripts/check_ports.sh" <<'CHECK_PORTS'
#!/usr/bin/env bash
set -euo pipefail
ss -ltnp | grep -E ':(8000|8001)\b' || true
CHECK_PORTS
chmod +x "${RUNTIME_DIR}/scripts/check_ports.sh"

echo
echo "[DONE] Runtime scripts are ready:"
ls -l "${RUNTIME_DIR}/scripts/run_vllm.sh" "${RUNTIME_DIR}/scripts/run_plant.sh"

echo
echo "[DONE] RunPod ports that must be exposed publicly:"
echo "  - ${QWEN_PORT}/tcp  -> Qwen vLLM OpenAI-compatible API"
echo "  - ${PLANT_PORT}/tcp -> Plant ConvNeXt FastAPI"

echo
echo "[DONE] Start Plant server in background, then Qwen vLLM in foreground:"
echo "cd ${RUNTIME_DIR}"
echo "source .env.runtime"
echo "bash scripts/run_plant.sh > /workspace/logs/plant.log 2>&1 &"
echo "bash scripts/run_vllm.sh"

echo
echo "[DONE] Health checks after startup:"
echo "curl -s http://127.0.0.1:${PLANT_PORT}/health | python3 -m json.tool"
echo "curl -s http://127.0.0.1:${QWEN_PORT}/v1/models | python3 -m json.tool"
