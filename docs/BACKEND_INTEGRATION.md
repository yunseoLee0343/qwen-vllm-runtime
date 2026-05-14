# Backend Integration Guide

## Overview

`sunshine_backend` connects to this runtime via an OpenAI-compatible HTTP endpoint.
The connection is configured through environment variables on the EC2 backend host.

---

## Environment Variables

Set these on the EC2 host running `sunshine_backend`:

```env
LLM_BACKEND=qwen
QWEN_LLM_MODEL=qwen3.6
QWEN_LLM_BASE_URL=https://abc123-8000.proxy.runpod.net
QWEN_LLM_TIMEOUT_SECONDS=120
```

Rules:
- `QWEN_LLM_BASE_URL` must **not** include `/v1/chat/completions` or a trailing slash.
- `QWEN_LLM_MODEL` must be `qwen3.6` (the `--served-model-name` passed to vLLM).
- `LLM_BACKEND=qwen` selects the Qwen code path inside `sunshine_backend`.

### Generate with the print script

```bash
bash scripts/print_backend_env.sh https://abc123-8000.proxy.runpod.net qwen3.6
```

Output:

```env
LLM_BACKEND=qwen
QWEN_LLM_MODEL=qwen3.6
QWEN_LLM_BASE_URL=https://abc123-8000.proxy.runpod.net
QWEN_LLM_TIMEOUT_SECONDS=120
```

---

## Dynamic Registry JSON (TICKET-055)

If `sunshine_backend` uses the dynamic endpoint registry instead of static env vars,
generate the registry JSON:

```bash
bash scripts/export_endpoint.sh https://abc123-8000.proxy.runpod.net qwen3.6
```

Produces `qwen_endpoint.json`:

```json
{
  "provider": "qwen",
  "model": "qwen3.6",
  "base_url": "https://abc123-8000.proxy.runpod.net",
  "api_key": null,
  "timeout_seconds": 120,
  "updated_at": "2026-05-14T12:00:00Z"
}
```

Push to the registry API:

```bash
curl -X PUT http://<ec2-host>:8000/internal/runtime-endpoints/qwen \
  -H "Content-Type: application/json" \
  -H "X-Internal-Token: ${INTERNAL_TOKEN}" \
  -d @qwen_endpoint.json
```

---

## Endpoint Contract

| Endpoint | Method | Description |
|---|---|---|
| `/v1/models` | GET | List loaded models — must include `qwen3.6` |
| `/v1/chat/completions` | POST | OpenAI-compatible chat completion |

### Chat completion request shape

```json
{
  "model": "qwen3.6",
  "messages": [
    {"role": "system", "content": "..."},
    {"role": "user",   "content": "..."}
  ],
  "max_tokens": 512,
  "temperature": 0.7,
  "stream": false
}
```

### Chat completion response shape

```json
{
  "id": "...",
  "object": "chat.completion",
  "choices": [
    {
      "index": 0,
      "message": {"role": "assistant", "content": "..."},
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 42,
    "completion_tokens": 18,
    "total_tokens": 60
  }
}
```

---

## Security Notes

- This endpoint has no built-in authentication when run as bare vLLM.
- For production, restrict access to the EC2 backend IP via RunPod firewall rules,
  or place an authenticating reverse proxy in front of vLLM.
- Never commit a long-lived public URL as a hard-coded constant in backend code.
- See `docs/TROUBLESHOOTING.md` for auth proxy options.
