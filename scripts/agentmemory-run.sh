#!/usr/bin/env bash
#
# agentmemory-run.sh  —  launcher for the agentmemory LaunchAgent
#
# Why a wrapper instead of invoking node directly from the plist: the
# consolidation worker checks `process.env["OBSIDIAN_AUTO_EXPORT"]` and reads
# `AGENTMEMORY_EXPORT_ROOT` straight from the OS environment, but nothing was
# injecting ~/.agentmemory/.env into the process — the plist only set PATH/HOME,
# and the cli->iii->worker spawn chain passes no env. So the Obsidian auto-export
# `if` branch was never entered (silent no-op). This wrapper sources the .env so
# every var in it reaches the worker, portably — no absolute paths baked into the
# plist. Mirrors scripts/litellm-router-run.sh.
#
# Overridable via env (defaults in brackets):
#   AGENTMEMORY_ENV_FILE  [~/.agentmemory/.env]
#   AGENTMEMORY_HOME      [~/.agentmemory]   engine cwd (pins ./data/state_store.db here)
#   AGENTMEMORY_NODE_BIN  [node on PATH]
#   AGENTMEMORY_CLI       [homebrew global, else `npm root -g`]

set -euo pipefail

ENV_FILE="${AGENTMEMORY_ENV_FILE:-$HOME/.agentmemory/.env}"
AM_HOME="${AGENTMEMORY_HOME:-$HOME/.agentmemory}"
NODE_BIN="${AGENTMEMORY_NODE_BIN:-$(command -v node || echo /opt/homebrew/bin/node)}"
CLI="${AGENTMEMORY_CLI:-/opt/homebrew/lib/node_modules/@agentmemory/agentmemory/dist/cli.mjs}"
[[ -f "$CLI" ]] || CLI="$(npm root -g 2>/dev/null)/@agentmemory/agentmemory/dist/cli.mjs"

[[ -x "$NODE_BIN" ]] || { echo "agentmemory-run: node not found/executable: $NODE_BIN" >&2; exit 1; }
[[ -f "$CLI" ]]      || { echo "agentmemory-run: cli.mjs not found: $CLI" >&2; exit 1; }

# Pin cwd so the engine's relative ./data/state_store.db resolves under
# ~/.agentmemory, never into whatever dir launchd/an MCP shim started from.
cd "$AM_HOME"

# Source .env into the environment so the worker's raw process.env reads
# (OBSIDIAN_AUTO_EXPORT, AGENTMEMORY_EXPORT_ROOT, ...) see it. Missing file is
# non-fatal — the daemon still starts, just without export.
if [[ -f "$ENV_FILE" ]]; then
    set -a; . "$ENV_FILE"; set +a
else
    echo "agentmemory-run: warning: $ENV_FILE not found; starting without it" >&2
fi

exec "$NODE_BIN" "$CLI" start
