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
