# Troubleshooting

## vLLM fails to start

### `CUDA out of memory`

Reduce `GPU_MEMORY_UTILIZATION` (e.g. from `0.90` to `0.80`) or reduce
`MAX_MODEL_LEN` (e.g. from `8192` to `4096`).

```bash
export GPU_MEMORY_UTILIZATION=0.80
export MAX_MODEL_LEN=4096
bash scripts/run_vllm.sh
```

### `Model path not found`

Confirm the model directory exists and contains the expected files:

```bash
ls /workspace/models/qwen3.6/
# Must include: config.json, tokenizer.json, model-*.safetensors
```

If running via Docker Compose, verify `MODEL_ROOT` in `.env` points to the parent
directory and that the directory is mounted correctly:

```bash
docker compose exec qwen-vllm ls /models/qwen3.6/
```

### `unknown runtime: nvidia` (Docker Compose)

Comment out the `runtime: nvidia` line in `docker-compose.yml`. RunPod pods already
expose GPUs without requiring this flag.

---

## `check_models.sh` returns connection refused

- vLLM may still be loading. Wait 60–120 seconds and retry.
- Confirm the port is exposed on RunPod dashboard (**Connect → Expose Port**).
- Confirm `VLLM_BASE_URL` does not end with a slash or path segment.

```bash
# Correct
export VLLM_BASE_URL=https://abc123-8000.proxy.runpod.net

# Wrong
export VLLM_BASE_URL=https://abc123-8000.proxy.runpod.net/v1/chat/completions
```

---

## `check_chat.sh` returns 404 or `model not found`

Confirm `--served-model-name qwen3.6` was passed to vLLM and that the `model`
field in the request body is exactly `qwen3.6`.

---

## `check_chat.sh` returns empty `content`

- Check `MAX_MODEL_LEN` — if the prompt exceeds it vLLM may truncate output.
- Try lowering temperature or increasing `max_tokens`.

---

## Security: exposing vLLM safely

Bare vLLM has no authentication.  Options from least to most effort:

| Option | Description |
|---|---|
| A | Use the endpoint only during dev/demo; stop the pod when done |
| B | Set RunPod firewall to allow only the EC2 backend IP |
| C | Run nginx/Caddy in front of vLLM and check `Authorization: Bearer <key>` |
| D | Use TICKET-055 `QWEN_LLM_API_KEY` support with a protected proxy |

Never publish a long-lived unauthenticated endpoint as production.

---

## Logs

### Bare script

vLLM logs go to stdout. Redirect to a file if needed:

```bash
bash scripts/run_vllm.sh 2>&1 | tee /workspace/vllm.log
```

### Docker Compose

```bash
docker compose logs -f qwen-vllm
```
