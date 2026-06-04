#!/usr/bin/env bash
#
# agentmemory-power-guard.sh
#
# Pauses agentmemory's GPU-heavy background loops while on battery, resumes
# them on AC. The loops (consolidation, reflection, graph extraction) call a
# local Ollama model (mistral:7b-instruct) which otherwise keeps the GPU warm
# permanently — fine on AC, unacceptable on battery.
#
# How it works (no engine restart needed):
#   agentmemory reads ~/.agentmemory/.env fresh on every flag check
#   (loadEnvFile() in dist/index.mjs — no caching, last-definition-wins), and
#   the cron functions re-check their gate at invocation time
#   (e.g. isConsolidationEnabled() inside mem::consolidate-pipeline). So
#   appending an override block at the END of .env flips the loops live:
#     - on battery -> block present, flags=false -> cron fires but bails early,
#       zero LLM calls -> Ollama unloads the model -> GPU idles.
#     - on AC      -> block removed -> the user's own `=true` lines win again.
#
# Triggered by com.nbrandizzi.agentmemory-power-guard (StartInterval poll).
# Idempotent: only writes .env on an actual battery<->AC transition.

set -euo pipefail

# ENV_FILE / OLLAMA_BIN / FORCE_POWER are overridable from the environment to
# allow isolated testing; they default to the real paths in normal operation.
ENV_FILE="${ENV_FILE:-${HOME}/.agentmemory/.env}"
LOG_FILE="${LOG_FILE:-${HOME}/Library/Logs/agentmemory/power-guard.log}"
OLLAMA_BIN="${OLLAMA_BIN:-/usr/local/bin/ollama}"

MARK_START="# >>> agentmemory-power-guard (managed) >>>"
MARK_END="# <<< agentmemory-power-guard (managed) <<<"

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null || true; }

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# --- power source --------------------------------------------------------
# Default to "on AC" (full power, no throttle) if detection is unclear, so a
# pmset hiccup never silently disables your memory loops.
on_battery() {
  # Test hook: FORCE_POWER=battery|ac bypasses pmset detection.
  case "${FORCE_POWER:-}" in
    battery) return 0 ;;
    ac)      return 1 ;;
  esac
  local batt
  batt="$(pmset -g batt 2>/dev/null || true)"
  [ -z "$batt" ] && return 1
  printf '%s' "$batt" | grep -q "AC Power" && return 1
  printf '%s' "$batt" | grep -q "Battery Power" && return 0
  return 1
}

block_present() {
  [ -f "$ENV_FILE" ] && grep -qF "$MARK_START" "$ENV_FILE"
}

add_block() {
  block_present && return 0
  {
    printf '\n%s\n' "$MARK_START"
    printf '# Auto-added while on battery to stop the local Ollama model pegging the GPU.\n'
    printf '# Removed automatically on AC. Last-definition-wins overrides the values above.\n'
    printf 'CONSOLIDATION_ENABLED=false\n'
    printf 'AGENTMEMORY_REFLECT=false\n'
    printf 'GRAPH_EXTRACTION_ENABLED=false\n'
    printf '%s\n' "$MARK_END"
  } >> "$ENV_FILE"
  log "battery: appended override block (loops disabled)"
}

remove_block() {
  block_present || return 0
  local tmp
  tmp="$(mktemp)"
  # Drop the managed block, then strip the trailing blank line(s) the block's
  # leading separator introduced, leaving the file ending in a single newline.
  awk -v s="$MARK_START" -v e="$MARK_END" '
    $0 == s { skip = 1 }
    skip    { if ($0 == e) skip = 0; next }
    { lines[NR] = $0; last = NR }
    END {
      # find last non-blank line
      end = 0
      for (i = 1; i <= last; i++) if (lines[i] ~ /[^[:space:]]/) end = i
      for (i = 1; i <= end; i++) print lines[i]
    }
  ' "$ENV_FILE" > "$tmp"
  mv "$tmp" "$ENV_FILE"
  log "AC: removed override block (loops re-enabled)"
}

unload_model() {
  [ -x "$OLLAMA_BIN" ] || return 0
  local model
  model="$(grep -E '^OPENAI_MODEL=' "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]')"
  [ -z "$model" ] && model="mistral:7b-instruct"
  # Drop the model from the GPU immediately; cron stays gated so it won't reload.
  "$OLLAMA_BIN" stop "$model" >/dev/null 2>&1 && log "unloaded ollama model: $model" || true
}

main() {
  if on_battery; then
    if ! block_present; then
      add_block
      unload_model
    fi
  else
    if block_present; then
      remove_block
    fi
  fi
}

main "$@"
