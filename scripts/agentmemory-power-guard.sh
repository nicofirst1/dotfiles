#!/usr/bin/env bash
#
# agentmemory-power-guard.sh
#
# Pauses agentmemory's GPU-heavy background loops ONLY when they would actually
# hit the local GPU — i.e. on battery AND the cloud LLM (FhGenie, via the
# LiteLLM router) is unreachable, so the router has fallen back to local Ollama.
#
# Why the FhGenie check: agentmemory's LLM now points at the LiteLLM router
# (OPENAI_BASE_URL=127.0.0.1:4141). Normally that routes to FhGenie MiniMax —
# remote, no local GPU, zero battery cost — so the loops are fine on battery.
# The local Ollama model (mistral:7b-instruct) is only used when FhGenie is
# unreachable (off-VPN / on-prem down). That is the one case where running the
# loops on battery would peg the M2 GPU. So:
#       throttle  <=>  on battery  AND  FhGenie unreachable
#
# How the throttle works (no engine restart needed):
#   agentmemory reads ~/.agentmemory/.env fresh on every flag check
#   (loadEnvFile() in dist/index.mjs — no caching, last-definition-wins), and
#   the cron functions re-check their gate at invocation time
#   (e.g. isConsolidationEnabled()). Appending an override block at the END of
#   .env flips the loops live; removing it restores the user's `=true` lines.
#
# Triggered by com.nbrandizzi.agentmemory-power-guard (StartInterval poll).
# Idempotent: only writes .env on an actual throttle<->unthrottle transition.

set -euo pipefail

# Overridable from the environment for isolated testing; defaults are the real
# paths/values in normal operation.
ENV_FILE="${ENV_FILE:-${HOME}/.agentmemory/.env}"
LOG_FILE="${LOG_FILE:-${HOME}/Library/Logs/agentmemory/power-guard.log}"
OLLAMA_BIN="${OLLAMA_BIN:-/usr/local/bin/ollama}"
KEY_FILE="${FHGENIE_KEY_FILE:-${HOME}/.employer-api-key}"

# Hysteresis: how many consecutive polls must agree on the NEW state before we
# actually flip .env. At the 30s poll interval, 3 => a 90s confirmation window.
# A lone flaky FhGenie probe (or a momentary AC blip) no longer churns .env or
# unloads the model. Tunable for testing.
STREAK_THRESHOLD="${STREAK_THRESHOLD:-3}"
# Persists the pending-transition streak across launchd invocations (the script
# runs fresh every poll, so in-memory counters don't survive).
STATE_FILE="${STATE_FILE:-${HOME}/.agentmemory/.power-guard-state}"
# How many times to probe FhGenie within a single run before declaring it down.
# Absorbs a single transient timeout without waiting for the next 30s poll.
FHGENIE_PROBES="${FHGENIE_PROBES:-2}"
# The real Ollama model the router falls back to (config/litellm memory-fallback).
# NOT OPENAI_MODEL from .env — that is now the router alias "memory-default".
AM_OLLAMA_MODEL="${AM_OLLAMA_MODEL:-mistral:7b-instruct}"

# FhGenie base URL: read from the key file if present, else default. We probe it
# unauthenticated (a 404 from /v1 still proves reachability), so no secret is
# needed here.
_fh_base=""
[ -f "$KEY_FILE" ] && _fh_base="$(grep -E '^BASE_URL=' "$KEY_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '[:space:]')"
FHGENIE_BASE_URL="${FHGENIE_BASE_URL:-${_fh_base:-https://fhgenie.fraunhofer.de/v1}}"

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

# --- cloud primary reachability ------------------------------------------
# True if FhGenie answers at all (any HTTP status, incl. 401/404) within the
# timeout. A connection failure/timeout yields code 000 -> unreachable. No auth
# header sent, so this never touches the API key.
fhgenie_reachable() {
  # Test hook: FORCE_FHGENIE=up|down bypasses the probe.
  case "${FORCE_FHGENIE:-}" in
    up)   return 0 ;;
    down) return 1 ;;
  esac
  local code i
  # Probe a few times within this single run: one transient timeout shouldn't
  # flip us to "unreachable". Any successful answer (incl. 401/404) wins early.
  for ((i = 0; i < FHGENIE_PROBES; i++)); do
    # curl already prints "000" on connection failure/timeout; do NOT add `|| echo
    # 000` — that double-appends to "000000" and reads as reachable. Empty (curl
    # absent) also counts as unreachable.
    code="$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$FHGENIE_BASE_URL" 2>/dev/null)"
    [ -n "$code" ] && [ "$code" != "000" ] && return 0
  done
  return 1
}

block_present() {
  [ -f "$ENV_FILE" ] && grep -qF "$MARK_START" "$ENV_FILE"
}

add_block() {
  block_present && return 0
  {
    printf '\n%s\n' "$MARK_START"
    printf '# Auto-added on battery while FhGenie is unreachable (router on local\n'
    printf '# Ollama fallback) to stop mistral pegging the GPU. Removed when back\n'
    printf '# on AC or when FhGenie returns. Last-definition-wins over the values above.\n'
    printf 'CONSOLIDATION_ENABLED=false\n'
    printf 'AGENTMEMORY_REFLECT=false\n'
    printf 'GRAPH_EXTRACTION_ENABLED=false\n'
    printf '%s\n' "$MARK_END"
  } >> "$ENV_FILE"
  log "throttle ON (battery + FhGenie unreachable): appended override block"
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
  log "throttle OFF: removed override block (loops re-enabled)"
}

unload_model() {
  [ -x "$OLLAMA_BIN" ] || return 0
  # Drop the local fallback model from the GPU immediately; cron stays gated so
  # it won't reload while throttled.
  "$OLLAMA_BIN" stop "$AM_OLLAMA_MODEL" >/dev/null 2>&1 \
    && log "unloaded ollama model: $AM_OLLAMA_MODEL" || true
}

# --- hysteresis state ----------------------------------------------------
# The pending-transition streak lives in one line: "<target> <count>", where
# target is the state we're trying to move TO (ON|OFF). Absent/empty == no
# pending transition (we're settled in the current state).
read_streak_target() { [ -f "$STATE_FILE" ] && awk '{print $1}' "$STATE_FILE" 2>/dev/null || true; }
read_streak_count()  { [ -f "$STATE_FILE" ] && awk '{print ($2 ~ /^[0-9]+$/) ? $2 : 0}' "$STATE_FILE" 2>/dev/null || true; }
write_streak()       { printf '%s %s\n' "$1" "$2" > "$STATE_FILE" 2>/dev/null || true; }
clear_streak()       { rm -f "$STATE_FILE" 2>/dev/null || true; }

main() {
  # Throttle only when the loops would actually burn the local GPU: on battery
  # AND FhGenie down (router fell back to Ollama). Every other combination
  # (AC, or FhGenie reachable) runs the loops — inference is remote or cheap.
  local want current
  if on_battery && ! fhgenie_reachable; then want="ON"; else want="OFF"; fi
  if block_present; then current="ON"; else current="OFF"; fi

  # Already where we want to be: cancel any half-built streak and stop. This is
  # the common case and writes nothing (idempotent, no churn).
  if [ "$want" = "$current" ]; then
    [ -f "$STATE_FILE" ] && clear_streak
    return 0
  fi

  # A flip is desired. Require STREAK_THRESHOLD consecutive polls agreeing on the
  # same target before acting, so a single flaky FhGenie probe / AC blip can't
  # rewrite .env or unload the model.
  local target count
  target="$(read_streak_target)"
  if [ "$target" = "$want" ]; then
    count=$(( $(read_streak_count) + 1 ))
  else
    count=1
  fi

  if [ "$count" -ge "$STREAK_THRESHOLD" ]; then
    clear_streak
    if [ "$want" = "ON" ]; then
      add_block
      unload_model
    else
      remove_block
    fi
  else
    write_streak "$want" "$count"
    log "pending throttle $want ($count/$STREAK_THRESHOLD) — holding $current until confirmed"
  fi
}

main "$@"
