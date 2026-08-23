#!/usr/bin/env bash
#
# backup-healthcheck.sh — answers the only question that matters: is there a
#                         recent, complete, restorable backup right now?
#
# This exists because the nightly path cannot answer it. Backrest runs
# backup-predump.sh as a CONDITION_SNAPSHOT_START hook with ON_ERROR_IGNORE, so
# a pre-dump that fails every single database still lets the backup proceed and
# still reports the plan as SUCCESS. That is the right trade -- a partial backup
# beats no backup -- but it means the script's careful STALE/ZOMBIE/dump-failed
# warnings have no audience. This is the audience.
#
# Run daily by backup-healthcheck.timer, after both plans. Non-zero exit puts
# the unit in `systemctl --failed`, so a silent rot shows up somewhere.
set -uo pipefail

RESTIC_ENV="${RESTIC_ENV:-$HOME/.config/restic/env}"
# shellcheck source=/dev/null
[[ -f "$RESTIC_ENV" ]] && source "$RESTIC_ENV"
export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-$HOME/.config/restic/password}"
export RCLONE_DRIVE_PACER_MIN_SLEEP="${RCLONE_DRIVE_PACER_MIN_SLEEP:-200ms}"
export RCLONE_DRIVE_PACER_BURST="${RCLONE_DRIVE_PACER_BURST:-1}"

STAGING="${BACKUP_STAGING:-/mnt/data/backup-staging}"
MAX_AGE_H="${BACKUP_MAX_AGE_HOURS:-36}"
problems=0

say()  { printf '%s\n' "$*"; }
first_problem=""
bad()  { printf 'PROBLEM: %s\n' "$*" >&2; problems=$((problems+1))
         [[ -z "$first_problem" ]] && first_problem="$*"; return 0; }

say "== backup health check $(date -Is) =="

# 1. The disk the local repo lives on.
if ! mountpoint -q /mnt/data; then
  bad "/mnt/data is not mounted — the local repo is unreachable"
else
  avail=$(df -BG --output=avail /mnt/data | tail -1 | tr -dc '0-9')
  say "  /mnt/data mounted, ${avail}G free"
  (( avail < 10 )) && bad "/mnt/data has only ${avail}G free"
fi

# 2. Staged dumps must be from the most recent run, not from some night weeks
#    ago when the store last dumped successfully.
if [[ -s "$STAGING/.manifest" ]]; then
  stale=0
  while IFS= read -r rel; do
    f="$STAGING/$rel"
    if [[ ! -f "$f" ]]; then
      bad "staged dump missing entirely: $rel"
    elif [[ -n "$(find "$f" -mmin "+$((MAX_AGE_H*60))" -print -quit 2>/dev/null)" ]]; then
      bad "staged dump older than ${MAX_AGE_H}h: $rel ($(date -r "$f" -Is))"
      stale=$((stale+1))
    fi
  done < "$STAGING/.manifest"
  say "  $(grep -c . "$STAGING/.manifest") staged dumps checked, $stale stale"
else
  bad "no staging manifest at $STAGING/.manifest — pre-dump has never completed"
fi

# 3. Both repos must hold a recent snapshot. This is the check that catches a
#    scheduler that quietly stopped firing, which is the failure this whole
#    exercise started from.
check_repo() {
  local name="$1" repo="$2"
  local latest
  latest=$(RESTIC_REPOSITORY="$repo" restic snapshots --json --latest 1 2>/dev/null \
           | jq -r '.[-1].time // empty' 2>/dev/null)
  if [[ -z "$latest" ]]; then
    bad "$name: no snapshots found (or repo unreachable)"; return
  fi
  local age_h
  age_h=$(( ( $(date +%s) - $(date -d "$latest" +%s) ) / 3600 ))
  if (( age_h > MAX_AGE_H )); then
    bad "$name: newest snapshot is ${age_h}h old (limit ${MAX_AGE_H}h) — $latest"
  else
    say "  $name: newest snapshot ${age_h}h old — OK"
  fi
}
check_repo local "${RESTIC_REPO_LOCAL:-/mnt/data/restic}"
check_repo drive "${RESTIC_REPO_DRIVE:-rclone:gdrive:}"

# 4. The repo password must exist off this machine, or both repos are ornaments.
#    We cannot verify escrow; we can at least refuse to let it be forgotten.
[[ -s "$RESTIC_PASSWORD_FILE" ]] || bad "restic password file missing at $RESTIC_PASSWORD_FILE"

# Report to Uptime Kuma, if a push monitor is configured.
#
# A push monitor is the right shape here, not an HTTP check. An HTTP monitor
# against Backrest's port only proves the web server is up -- which it will be
# on the night every database dump fails and the plan still reports SUCCESS.
# This pushes the answer to "is there a recent, complete, restorable backup",
# and Kuma alerts on the ABSENCE of a push, so a healthcheck that never runs at
# all is itself the alarm. An HTTP monitor cannot detect that.
#
# Set BACKUP_KUMA_PUSH_URL in ~/.config/restic/env to the push URL Kuma gives
# you (the .../api/push/<token> form, without any query string).
if [[ -n "${BACKUP_KUMA_PUSH_URL:-}" ]]; then
  if (( problems )); then
    kuma_status="down"; kuma_msg="$problems problem(s): $(printf '%s' "${first_problem:-see journal}")"
  else
    kuma_status="up";   kuma_msg="ok"
  fi
  curl -fsS -m 10 -G "$BACKUP_KUMA_PUSH_URL" \
       --data-urlencode "status=$kuma_status" \
       --data-urlencode "msg=$kuma_msg" >/dev/null 2>&1 \
    || say "  (note: could not reach Kuma at $BACKUP_KUMA_PUSH_URL)"
fi

if (( problems )); then
  say "== $problems problem(s) — backups are NOT healthy =="
  exit 1
fi
say "== all checks passed =="
