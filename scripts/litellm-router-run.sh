#!/usr/bin/env bash
#
# litellm-router-run.sh  —  launcher for the LiteLLM router LaunchAgent
#
# Sources the IAIS GenAI credentials out of ~/.secrets.env (kept OUT of the
# repo and out of the plist), then execs the pipx-isolated litellm proxy
# against config/litellm/config.yaml.
#
# IAIS GenAI (genai.iais.fraunhofer.de/api/v2) uses a bearer API key (2026-07,
# was HTTP Basic before). The config resolves it directly via
# api_key: os.environ/FHG_API_KEY - no header rewriting needed.
#
# The pipx-isolated binary is used by absolute path on purpose: a broken
# `litellm` shim may sit earlier on PATH (e.g. a pyenv global with mismatched
# fastapi). See scripts/install-litellm-router.sh.
#
# Overridable via env (defaults in brackets):
#   FHGENIE_KEY_FILE  [~/.secrets.env]        file with BASE_URL= and API_KEY=
#   LITELLM_BIN       [~/.local/bin/litellm]  pipx-installed proxy binary
#   LITELLM_CONFIG    [<repo>/config/litellm/config.yaml]
#   LITELLM_HOST      [127.0.0.1]
#   LITELLM_PORT      [4141]

set -euo pipefail

KEY_FILE="${FHGENIE_KEY_FILE:-$HOME/.secrets.env}"
LITELLM_BIN="${LITELLM_BIN:-$HOME/.local/bin/litellm}"
HOST="${LITELLM_HOST:-127.0.0.1}"
PORT="${LITELLM_PORT:-4141}"

# Resolve the repo dir from this script's own location -> portable across clones.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${LITELLM_CONFIG:-$SELF/../config/litellm/config.yaml}"

[[ -f "$KEY_FILE" ]] || { echo "litellm-router: key file not found: $KEY_FILE" >&2; exit 1; }
[[ -x "$LITELLM_BIN" ]] || { echo "litellm-router: litellm not found/executable: $LITELLM_BIN" >&2; exit 1; }
[[ -f "$CONFIG" ]] || { echo "litellm-router: config not found: $CONFIG" >&2; exit 1; }

# Load the key file; the config resolves FHG_API_KEY / IAIS_BASE_URL directly
# via os.environ/... - no header rewriting needed.
set -a; . "$KEY_FILE"; set +a
: "${FHG_API_KEY:?FHG_API_KEY missing in $KEY_FILE}"
export IAIS_BASE_URL="$(printf '%s' "${IAIS_BASE_URL:-https://genai.iais.fraunhofer.de/api/v2}" | tr -d '[:space:]')"

exec "$LITELLM_BIN" --config "$CONFIG" --host "$HOST" --port "$PORT"
