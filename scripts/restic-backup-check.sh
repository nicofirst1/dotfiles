#!/usr/bin/env bash
#
# restic-backup-check.sh  —  dead-man's-switch for the daily restic backup.
#
# Claude Code auto-deletes session transcripts after ~30 days (cleanupPeriodDays,
# default 30). backup-restic.sh runs daily to capture them before they age out.
# The one way to silently lose data is that daily job stalling (Drive creds
# expire, rclone breaks, agent unloaded) unnoticed for >30 days — exactly the
# shape of the agentmemory outage that ran 5 weeks silent.
#
# This closes that gap: it asks restic for the newest snapshot. That single call
# proves the repo is REACHABLE (creds + network ok) AND RECENT. Healthy => silent
# (a dead-man's-switch nags only on failure). Stale or unreachable => a macOS
# notification. Run weekly by com.nbrandizzi.restic-backup-check.
#
# ponytail: no state file, no metrics — the restic repo IS the source of truth.

set -euo pipefail

# Same repo/creds plumbing as backup-restic.sh (machine-specific, gitignored).
RESTIC_ENV="${RESTIC_ENV:-$HOME/.config/restic/env}"
# shellcheck source=/dev/null
[[ -f "$RESTIC_ENV" ]] && source "$RESTIC_ENV"
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-rclone:gdrive:}"
export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-$HOME/.config/restic/password}"

# Backup is daily; 3 days tolerates the Mac being asleep a night or two without
# crying wolf, while still catching a real stall ~4 weeks before the 30-day cliff.
MAX_AGE_DAYS="${MAX_AGE_DAYS:-3}"

notify() {  # $1 = message. Native macOS banner — no dependency.
    osascript -e "display notification \"$1\" with title \"Restic backup check\" sound name \"Basso\"" 2>/dev/null || true
    printf 'restic-backup-check: ALERT: %s\n' "$1" >&2
}

command -v restic >/dev/null 2>&1 || { notify "restic missing on PATH"; exit 1; }

# Newest snapshot as JSON. A failure here means the repo is unreachable (dead
# creds, Drive down, lock) — itself a backup-is-not-working signal, so alert.
if ! json=$(restic snapshots --tag claude-hermes --latest 1 --json 2>/dev/null); then
    notify "cannot reach restic repo (creds/network/lock?) — backup may be broken"
    exit 1
fi

# Parse the snapshot time and compare to now. python3 ships on macOS and already
# powers other scripts here (audit-unused.py); avoids a jq dependency.
age_days=$(printf '%s' "$json" | python3 -c '
import sys, json, datetime
snaps = json.load(sys.stdin)
if not snaps:
    print("EMPTY"); sys.exit(0)
t = snaps[-1]["time"].split(".")[0].rstrip("Z")          # drop subsecond/zone noise
dt = datetime.datetime.fromisoformat(t)
now = datetime.datetime.now(dt.tzinfo) if dt.tzinfo else datetime.datetime.now()
print(int((now - dt).total_seconds() // 86400))
') || { notify "could not parse restic snapshot output"; exit 1; }

if [[ "$age_days" == "EMPTY" ]]; then
    notify "restic repo has NO claude-hermes snapshots — backup never succeeded"
    exit 1
fi

if (( age_days > MAX_AGE_DAYS )); then
    notify "last backup was ${age_days}d ago (>${MAX_AGE_DAYS}d) — daily backup has stalled"
    exit 1
fi

printf 'restic-backup-check: ok — last snapshot %sd old (<=%sd)\n' "$age_days" "$MAX_AGE_DAYS"
