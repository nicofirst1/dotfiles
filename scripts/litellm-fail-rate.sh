#!/usr/bin/env bash
#
# litellm-fail-rate.sh — HTTP status breakdown + failure rate for the
# LiteLLM router's access log. A cheap way to check "is the GPU hot because
# agentmemory is falling back to Ollama a lot, or is that background noise".
#
# Counts are cumulative since the router last (re)started - launchd appends
# to this log and there are no per-line timestamps, so this isn't scoped to
# "today". Restart the router (or truncate the log) to reset the window.
#
# Usage: litellm-fail-rate.sh [logfile]

set -euo pipefail

LOG="${1:-$HOME/Library/Logs/litellm/litellm-router.stdout.log}"
[[ -f "$LOG" ]] || { echo "litellm-fail-rate: log not found: $LOG" >&2; exit 1; }

grep -oE '" [0-9]{3} ' "$LOG" | tr -d '"' | sort | uniq -c | sort -rn | awk '
  { print; total += $1; if ($2 !~ /^2/) fail += $1 }
  END { printf "\n%d/%d requests failed (%.2f%%)\n", fail, total, (total ? 100*fail/total : 0) }
'
