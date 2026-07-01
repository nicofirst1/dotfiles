#!/usr/bin/env bash
#
# litellm-router-run.sh  —  launcher for the LiteLLM router LaunchAgent
#
# Sources the IAIS GenAI credentials out of ~/.employer-api-key (kept OUT of the
# repo and out of the plist), builds the Basic-auth header the config expects,
# then execs the pipx-isolated litellm proxy against config/litellm/config.yaml.
#
# IAIS GenAI (genai.iais.fraunhofer.de/api/v2) uses HTTP Basic auth
# (base64 user:pass), not a Bearer key. LiteLLM sends Bearer by default, so we
# pass the Basic header via the config's extra_headers -> os.environ/IAIS_AUTH_HEADER.
#
# The pipx-isolated binary is used by absolute path on purpose: a broken
# `litellm` shim may sit earlier on PATH (e.g. a pyenv global with mismatched
# fastapi). See scripts/install-litellm-router.sh.
#
# Overridable via env (defaults in brackets):
#   FHGENIE_KEY_FILE  [~/.employer-api-key]   file with BASE_URL= and API_KEY=
#   LITELLM_BIN       [~/.local/bin/litellm]  pipx-installed proxy binary
#   LITELLM_CONFIG    [<repo>/config/litellm/config.yaml]
#   LITELLM_HOST      [127.0.0.1]
#   LITELLM_PORT      [4141]

set -euo pipefail

KEY_FILE="${FHGENIE_KEY_FILE:-$HOME/.employer-api-key}"
LITELLM_BIN="${LITELLM_BIN:-$HOME/.local/bin/litellm}"
HOST="${LITELLM_HOST:-127.0.0.1}"
PORT="${LITELLM_PORT:-4141}"

# Resolve the repo dir from this script's own location -> portable across clones.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${LITELLM_CONFIG:-$SELF/../config/litellm/config.yaml}"

[[ -f "$KEY_FILE" ]] || { echo "litellm-router: key file not found: $KEY_FILE" >&2; exit 1; }
[[ -x "$LITELLM_BIN" ]] || { echo "litellm-router: litellm not found/executable: $LITELLM_BIN" >&2; exit 1; }
[[ -f "$CONFIG" ]] || { echo "litellm-router: config not found: $CONFIG" >&2; exit 1; }

# Load the key file and build the Basic-auth header the config resolves via
# os.environ/IAIS_AUTH_HEADER / os.environ/IAIS_BASE_URL.
set -a; . "$KEY_FILE"; set +a
: "${FHG_USERNAME:?FHG_USERNAME missing in $KEY_FILE}"
: "${FHG_PASSWORD:?FHG_PASSWORD missing in $KEY_FILE}"
export IAIS_BASE_URL="$(printf '%s' "${IAIS_BASE_URL:-https://genai.iais.fraunhofer.de/api/v2}" | tr -d '[:space:]')"
# `base64` on macOS emits no line wraps for short input; strip any stray newline anyway.
export IAIS_AUTH_HEADER="Basic $(printf '%s:%s' "$FHG_USERNAME" "$FHG_PASSWORD" | base64 | tr -d '\n')"

exec "$LITELLM_BIN" --config "$CONFIG" --host "$HOST" --port "$PORT"
