#!/usr/bin/env bash
#
# install-litellm-router.sh  —  standalone LiteLLM-router provisioner
#
# NOT called by installation.sh on purpose (same policy as install-agentmemory.sh):
# this depends on an employer API key and only makes sense on a machine that has
# one. Run it by hand:
#
#     bash ~/dotfiles/scripts/install-litellm-router.sh
#
# What it does — point agentmemory's LLM work at Fraunhofer IAIS GenAI (fast,
# free, employer-paid, non-reasoning models) with local Ollama as an automatic
# fallback:
#   1. litellm[proxy]                 -> pipx (isolated venv; the pyenv shim is
#                                        dependency-broken, so we never use it)
#   2. preflight                       -> ~/.secrets.env, IAIS reachable,
#                                        Ollama up (fallback path)
#   3. the LaunchAgent (router :4000)  -> stowed + loaded
#   4. health + smoke test             -> memory-default answers via the proxy
#   5. ~/.agentmemory/.env             -> repointed at the router (backed up first)
#   6. agentmemory worker              -> kickstarted to pick up the new provider
#
# Idempotent: re-running re-validates and repoints again from a fresh backup.
# Embeddings are deliberately left LOCAL (no reindex). macOS only.
#
# Reverting: restore the printed ~/.agentmemory/.env.pre-litellm.* backup and
# `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.nbrandizzi.litellm-router.plist`.

set -euo pipefail

ROUTER_LABEL="com.nbrandizzi.litellm-router"
ROUTER_URL="http://127.0.0.1:4141"
KEY_FILE="${FHGENIE_KEY_FILE:-$HOME/.secrets.env}"
LITELLM_BIN="$HOME/.local/bin/litellm"
LOG_DIR="$HOME/Library/Logs/litellm"

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SELF/.." && pwd)"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

agent_loaded() { launchctl list 2>/dev/null | awk -v l="$1" '$3==l{f=1} END{exit f?0:1}'; }

# --- preconditions ----------------------------------------------------------
[[ "$OSTYPE" == darwin* ]] || die "macOS only (uses launchctl)."
command -v pipx >/dev/null || die "pipx missing — 'brew install pipx' first."
[[ -f "$KEY_FILE" ]] || die "key file $KEY_FILE not found. Create it with:
    printf 'FHG_USERNAME=%s\\nFHG_PASSWORD=%s\\nIAIS_BASE_URL=%s\\n' 'YOUR_USER' 'YOUR_PASS' 'https://genai.iais.fraunhofer.de/api/v2' > $KEY_FILE"

# Pull IAIS creds out of the key file for preflight probes (Basic auth).
set -a; . "$KEY_FILE"; set +a
[[ -n "${FHG_USERNAME:-}" ]] || die "FHG_USERNAME missing in $KEY_FILE"
[[ -n "${FHG_PASSWORD:-}" ]] || die "FHG_PASSWORD missing in $KEY_FILE"
IAIS_BASE_URL="$(printf '%s' "${IAIS_BASE_URL:-https://genai.iais.fraunhofer.de/api/v2}" | tr -d '[:space:]')"
IAIS_AUTH="Basic $(printf '%s:%s' "$FHG_USERNAME" "$FHG_PASSWORD" | base64 | tr -d '\n')"

# --- 1. litellm[proxy] via pipx (isolated) ----------------------------------
if "$LITELLM_BIN" --version >/dev/null 2>&1; then
    say "litellm already installed ($("$LITELLM_BIN" --version 2>&1 | grep -i version | tail -1))."
else
    # Pin to a 3.11/3.12 interpreter — pipx's default may be 3.14, which litellm
    # doesn't support yet.
    PYBIN=""
    for c in python3.12 python3.11; do
        command -v "$c" >/dev/null 2>&1 && { PYBIN="$(command -v "$c")"; break; }
    done
    [[ -n "$PYBIN" ]] || { PYBIN="$(command -v python3)"; warn "no python3.11/3.12 found; using $PYBIN"; }
    say "Installing litellm[proxy] via pipx (python: $PYBIN)..."
    UV_HTTP_TIMEOUT=180 PIP_DEFAULT_TIMEOUT=180 \
        pipx install --python "$PYBIN" "litellm[proxy]" --force \
        || die "pipx install failed (check network / VPN routing to pypi)."
    "$LITELLM_BIN" --version >/dev/null 2>&1 || die "litellm still not runnable at $LITELLM_BIN"
fi

# --- 2. preflight: IAIS reachable? Ollama up? -------------------------------
say "Probing IAIS GenAI ($IAIS_BASE_URL)..."
if curl -fsS -m 20 "$IAIS_BASE_URL/models" -H "Authorization: $IAIS_AUTH" >/dev/null 2>&1; then
    echo "  • IAIS GenAI: reachable"
else
    warn "IAIS not reachable (VPN down?). Router still installs; it will serve"
    warn "  from the Ollama fallback until IAIS comes back."
fi
if curl -fsS -m 4 "http://localhost:11434/api/version" >/dev/null 2>&1; then
    echo "  • Ollama (fallback): up"
else
    warn "Ollama not up at :11434 — the fallback path won't work until it is"
    warn "  (run install-agentmemory.sh, or start Ollama)."
fi

# --- 3. LaunchAgent: stow + load --------------------------------------------
mkdir -p "$LOG_DIR"
if command -v stow >/dev/null; then
    say "Stowing the launchagents package..."
    stow --dir="$DOTFILES_DIR" --target="$HOME" --restow launchagents
else
    warn "stow not found — symlink the plist manually."
fi

TARGET="$HOME/Library/LaunchAgents/$ROUTER_LABEL.plist"
if agent_loaded "$ROUTER_LABEL"; then
    say "Router already loaded — restarting to pick up config..."
    launchctl kickstart -k "gui/$(id -u)/$ROUTER_LABEL" 2>/dev/null || warn "kickstart failed."
elif [[ -e "$TARGET" ]]; then
    say "Loading $ROUTER_LABEL..."
    launchctl bootstrap "gui/$(id -u)" "$TARGET" 2>/dev/null \
        || warn "could not bootstrap $ROUTER_LABEL (load manually after next login)."
else
    warn "plist not found at $TARGET — stow step did not link it."
fi

# --- 4. wait for proxy health + smoke test ----------------------------------
say "Waiting for the router on $ROUTER_URL..."
for _ in $(seq 1 40); do
    curl -fsS -m 2 "$ROUTER_URL/health/liveliness" >/dev/null 2>&1 && break
    sleep 1
done
curl -fsS -m 2 "$ROUTER_URL/health/liveliness" >/dev/null 2>&1 \
    || die "router never became healthy — see $LOG_DIR/litellm-router.stderr.log"

say "Smoke-testing memory-default through the router..."
SMOKE="$(curl -sS -m 90 "$ROUTER_URL/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{"model":"memory-default","messages":[{"role":"user","content":"Reply with exactly: router-ok"}],"max_tokens":2048}' \
        | python3 -c 'import sys,json
try:
  d=json.load(sys.stdin); print((d["choices"][0]["message"].get("content") or "").strip()[:60])
except Exception as e: print("ERR:"+str(e))' 2>/dev/null)"
if [[ "$SMOKE" == ERR:* || -z "$SMOKE" ]]; then
    die "smoke test failed ($SMOKE). Not repointing agentmemory — your existing config is untouched."
fi
echo "  • model replied: $SMOKE"

# --- 5. repoint ~/.agentmemory/.env (backed up first) -----------------------
ENV_FILE="$HOME/.agentmemory/.env"
if [[ -f "$ENV_FILE" ]]; then
    BACKUP="$ENV_FILE.pre-litellm.$(date +%Y%m%d%H%M%S)"
    cp "$ENV_FILE" "$BACKUP"
    say "Backed up .env -> $BACKUP"
    say "Repointing agentmemory LLM at the router (embeddings stay local)..."
    python3 - "$ENV_FILE" <<'PY'
import sys, re
path = sys.argv[1]
# Only the LLM endpoint changes; embeddings stay local (no reindex). The router
# primary is now a NON-reasoning model (IAIS Mistral-Small), so there is no
# hidden-reasoning token drain; 8192 is ample headroom for batch graph-extraction
# JSON. Active (uncommented) lines are rewritten in place; any missing key is
# appended under a managed marker. Commented lines (e.g. a parked cloud key) are
# left untouched.
updates = {
    "OPENAI_API_KEY":  "litellm-local",        # dummy; the loopback proxy needs no auth
    "OPENAI_MODEL":    "memory-default",        # the router alias
    "OPENAI_BASE_URL": "http://127.0.0.1:4141", # agentmemory appends /v1/chat/completions
    "MAX_TOKENS":      "8192",
}
lines = open(path).read().splitlines()
seen, out = set(), []
for ln in lines:
    m = re.match(r'^(\s*)([A-Z0-9_]+)=', ln)
    if m and m.group(2) in updates:
        k = m.group(2)
        out.append(f"{k}={updates[k]}")
        seen.add(k)
    else:
        out.append(ln)
missing = [k for k in updates if k not in seen]
if missing:
    out += ["", "# --- repointed to LiteLLM router by install-litellm-router.sh ---"]
    out += [f"{k}={updates[k]}" for k in missing]
open(path, "w").write("\n".join(out) + "\n")
print("  • set: " + ", ".join(updates))
PY

    # --- 6. restart the agentmemory worker so it reads the new provider -----
    if agent_loaded com.nbrandizzi.agentmemory; then
        say "Restarting agentmemory worker..."
        launchctl kickstart -k "gui/$(id -u)/com.nbrandizzi.agentmemory" 2>/dev/null \
            || warn "kickstart failed; restart agentmemory manually."
    fi
else
    warn "no $ENV_FILE — run install-agentmemory.sh first, then re-run this."
fi

# --- done -------------------------------------------------------------------
say "LiteLLM router provisioned. Status:"
agent_loaded "$ROUTER_LABEL"            && echo "  • Router agent: loaded"  || echo "  • Router agent: NOT loaded"
curl -fsS -m 2 "$ROUTER_URL/health/liveliness" >/dev/null 2>&1 \
                                        && echo "  • Router $ROUTER_URL: healthy" || echo "  • Router $ROUTER_URL: DOWN"
echo
echo "agentmemory now: LLM -> IAIS Mistral-Small (fallback: Ollama mistral), embeddings -> local."
echo "Logs: $LOG_DIR/litellm-router.stderr.log"
echo "Manual switch of primary model: edit config/litellm/config.yaml (memory-default), re-run this script."
