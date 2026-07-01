# LiteLLM router — Fraunhofer IAIS GenAI (primary) + local Ollama (fallback)

A tiny local proxy that exposes ONE stable OpenAI-compatible endpoint
(`http://127.0.0.1:4141/v1`) and routes to Fraunhofer **IAIS GenAI**, with
automatic fallback to a **local Ollama** model when IAIS is unreachable
(off-VPN / off-net). Used here to point [agentmemory](../../scripts/install-agentmemory.sh)
at a fast remote LLM without giving up an offline path — but it's a generic
router: any OpenAI-compatible client can use it.

## Why a router (not a direct client)

- **IAIS uses HTTP Basic auth** (base64 `user:pass`), not a Bearer key. A plain
  OpenAI client sends `Authorization: Bearer …`; the router injects the Basic
  header via `extra_headers` instead.
- **Per-provider model mapping** makes fallback actually work: each alias carries
  its own provider+model, so IAIS→Ollama failover routes correctly instead of
  sending the primary's model name to the fallback (which would 404).

## Files

| File | Role |
|------|------|
| `config.yaml` | the router: aliases, providers, timeouts, fallback chain |
| [`../../scripts/litellm-router-run.sh`](../../scripts/litellm-router-run.sh) | launcher — builds the Basic-auth header from `~/.employer-api-key`, execs litellm |
| [`../../scripts/install-litellm-router.sh`](../../scripts/install-litellm-router.sh) | one-shot provisioner (pipx litellm, preflight, LaunchAgent, repoint agentmemory) — macOS |
| `../../launchagents/Library/LaunchAgents/com.nbrandizzi.litellm-router.plist` | keeps it running (macOS launchd) |

## Prerequisites

1. **litellm** (isolated): `pipx install "litellm[proxy]"` (needs pipx; Python 3.11/3.12).
2. **Your IAIS creds** in `~/.employer-api-key` (`chmod 600`), NOT in this repo:
   ```
   FHG_USERNAME=your_iais_username
   FHG_PASSWORD=your_iais_password
   IAIS_BASE_URL=https://genai.iais.fraunhofer.de/api/v2
   ```
3. **Fallback (optional):** [Ollama](https://ollama.com) running + `ollama pull mistral:7b-instruct`.
   Don't want a fallback? Delete the `memory-fallback` block and the `fallbacks:` line in `config.yaml`.

## Run

Manual (any OS):
```bash
LITELLM_CONFIG="$PWD/config.yaml" bash ../../scripts/litellm-router-run.sh
# -> http://127.0.0.1:4141
```
macOS, as a managed service: `bash scripts/install-litellm-router.sh` (stows +
loads the LaunchAgent, restarts on login). On Linux, wrap the run script in a
systemd unit.

Point your client at base URL `http://127.0.0.1:4141/v1`, model `memory-default`
(any API-key string — the loopback proxy ignores it; real auth is injected by the
runner).

## Smoke test

```bash
curl -s http://127.0.0.1:4141/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"memory-default","messages":[{"role":"user","content":"say OK"}],"max_tokens":10}'
```

## Model aliases (in `config.yaml`)

- `memory-default` — primary; `Mistral-Small-3.2-24B` (fast, **non-reasoning** →
  good for structured/JSON work, predictable token budgets).
- `memory-fallback` — local Ollama `mistral:7b-instruct`, used only when IAIS is unreachable.
- `iais-mistral-small`, `iais-qwen-122b`, `iais-gpt-oss-120b`, `ollama-mistral` —
  direct aliases for manual use / debugging (not in the auto fallback chain).

Swap the primary by editing `memory-default`'s `model:`. If you pick a **reasoning**
model, give `max_tokens` headroom — reasoning tokens are spent before the visible
answer and will otherwise truncate JSON mid-object.

## Security

No secrets live in this repo. `config.yaml` references creds via `os.environ/…`;
the runner reads them from `~/.employer-api-key` (outside the repo tree) at launch
and builds the `Authorization: Basic` header in-process.
