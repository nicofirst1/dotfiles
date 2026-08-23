#!/usr/bin/env bash
#
# backup-ublion.sh — nightly encrypted backup of Ublion's irreplaceable state to
#                    two independent restic repos.
#
# Companion to backup-restic.sh (the Mac-era agent-data backup). Two repos, not
# one, because they fail differently:
#   local  /mnt/data/restic  — a *different physical disk* (sda, 232 GB), so it
#                              survives the single-NVMe-failure case, and restores
#                              at disk speed with no bandwidth cost.
#   drive  rclone:gdrive:    — survives the whole machine: fire, theft, and the
#                              "both disks were in the same box" case.
#
# Nothing here reads a live database. backup-predump.sh stages consistent dumps
# of every SQLite/Redis/Qdrant/MariaDB store into $STAGING first, and the live
# files are excluded below — see that script for why per-store risk differs.
#
# Provisioned by install-backup-ublion.sh; run by backup-ublion.timer (daily).
set -uo pipefail

RESTIC_ENV="${RESTIC_ENV:-$HOME/.config/restic/env}"
# shellcheck source=/dev/null
[[ -f "$RESTIC_ENV" ]] || { echo "backup-ublion: no $RESTIC_ENV — run install-backup-ublion.sh" >&2; exit 2; }
source "$RESTIC_ENV"

WHICH="${1:-both}"     # local | drive | both
case "$WHICH" in
  local|drive|both) ;;
  *) echo "backup-ublion: unknown target '$WHICH' (want local|drive|both)" >&2; exit 2;;
esac
TAG="ublion"
# Exported so backup-predump.sh writes where this script reads. Defining it
# independently in both scripts invites them to drift apart silently.
export BACKUP_STAGING="${BACKUP_STAGING:-/mnt/data/backup-staging}"
STAGING="$BACKUP_STAGING"
PREDUMP="${PREDUMP:-$HOME/bin/backup-predump.sh}"

# Google Drive rate-limits hard on bursts of small uploads, worse through
# rclone's shared worldwide API client: a first full run hits RATE_LIMIT_EXCEEDED
# and repeated HTTP 500. Fewer+bigger packs, capped connections, gentle pacing.
# These values are the ones already proven on the Mac repo — do not re-derive.
export RCLONE_DRIVE_PACER_MIN_SLEEP="${RCLONE_DRIVE_PACER_MIN_SLEEP:-200ms}"
export RCLONE_DRIVE_PACER_BURST="${RCLONE_DRIVE_PACER_BURST:-1}"
export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-$HOME/.config/restic/password}"

die() { printf 'backup-ublion: %s\n' "$*" >&2; exit 2; }
say() { printf '%s == %s\n' "$(date -Is)" "$*"; }

command -v restic >/dev/null || die "restic missing"
[[ -n "${RESTIC_REPO_LOCAL:-}" && -n "${RESTIC_REPO_DRIVE:-}" ]] \
  || die "$RESTIC_ENV does not define RESTIC_REPO_LOCAL and RESTIC_REPO_DRIVE"
[[ -f "$RESTIC_PASSWORD_FILE" ]] || die "no password file at $RESTIC_PASSWORD_FILE"
mountpoint -q /mnt/data || die "/mnt/data is not mounted — refusing to run"

# --- 1. consistent snapshots ------------------------------------------------
say "pre-dump"
if ! "$PREDUMP"; then
  # A partial dump is still worth backing up — yesterday's copy of one store is
  # better than no run at all — but it must not pass silently.
  echo "backup-ublion: WARNING pre-dump reported failures (see above)" >&2
  PREDUMP_RC=1
else
  PREDUMP_RC=0
fi

# --- 2. what to keep --------------------------------------------------------
# Rule: back up what cannot be recreated. Anything reinstallable (venvs, node
# trees, LSP servers, vendored binaries) or regenerable (caches, logs, sandboxes)
# is excluded — it is 90% of the bytes and 0% of the value.
TARGETS=(
  "$STAGING"                       # the DB dumps — the real payload
  "$HOME/.hermes"
  "$HOME/.frigate/config"
  "$HOME/repos"
  "$HOME/memory-os"
  "$HOME/.actual"
  "$HOME/.config/claude"
  "$HOME/.config/rclone"
  "$HOME/.ssh"
  "$HOME/agent" "$HOME/skills" "$HOME/data"
  "$HOME/caddy-setup" "$HOME/searxng"
)
for f in "$HOME/.secrets.env" "$HOME/.gitconfig" "$HOME/.zshrc" "$HOME/.bashrc"; do
  [[ -e "$f" ]] && TARGETS+=("$f")
done

EXCLUDES=(
  --exclude-caches
  # Reinstallable code trees, not data.
  --exclude "$HOME/.hermes/hermes-agent"
  --exclude "$HOME/.hermes/hermes-agent-old-*"
  --exclude "$HOME/.hermes/venvs"
  --exclude "$HOME/.hermes/node"
  --exclude "$HOME/.hermes/bin"
  --exclude "$HOME/.hermes/lsp"
  --exclude "$HOME/.hermes/tmp"
  --exclude "$HOME/.hermes/cache"
  --exclude "$HOME/.hermes/logs"
  --exclude "$HOME/.hermes/sandboxes"
  --exclude "$HOME/.hermes/audio_cache"
  --exclude "$HOME/.hermes/image_cache"
  --exclude "$HOME/.hermes/profiles/*/home/.cache"
  --exclude "$HOME/.hermes/profiles/*/lsp"
  --exclude "$HOME/.hermes/profiles/*/bin"
  --exclude "$HOME/.hermes/profiles/*/cache"
  --exclude "$HOME/.hermes/profiles/*/logs"
  --exclude "$HOME/.hermes/*_cache.json"
  # (Live-database excludes are appended below, generated from predump's own
  #  source list -- see the note there.)
  # Firefly's MariaDB datadir is raw InnoDB owned by the container's mysql uid:
  # unreadable here, and worthless anyway — the mariadb-dump in staging is the
  # restorable form. Excluding it is what keeps this run off restic's rc=3.
  --exclude "$HOME/repos/personal/firefly-iii/db"
  # Regenerable build/dep trees (~6 GB of .venv alone).
  --exclude "**/.venv" --exclude "**/venv" --exclude "**/node_modules"
  --exclude "**/__pycache__" --exclude "**/*.pyc"
  --exclude "**/target/debug" --exclude "**/.next" --exclude "**/.pytest_cache"
  --exclude "**/.mypy_cache" --exclude "**/.ruff_cache"
  --exclude "**/.DS_Store" --exclude "**/*.sock"
  # NB: no "**/*.lock" here. It looks regenerable but is not -- uv.lock/yarn.lock
  # pin exact versions, and re-resolving yields different ones.
  --exclude "**/*.pid"
)

# Exclude every live database that predump stages, generated from predump's own
# discovery so the two lists cannot drift. A hand-maintained pair silently put
# 54 MB of prbot state in no backup at all (excluded here, never dumped there)
# while reading four other databases live. One list, derived twice.
# predump regenerates this on every run from its own discovery, so this script
# and Backrest consume the identical list and neither can drift from it.
EXCLUDE_FILE="$STAGING/.restic-excludes"
[[ -s "$EXCLUDE_FILE" ]] || die "predump did not write $EXCLUDE_FILE — refusing to back up live DB files"
EXCLUDES+=( --exclude-file "$EXCLUDE_FILE" )
say "excluding $(grep -c . "$EXCLUDE_FILE") live database paths (staged dumps are backed up instead)"

run_repo() {
  local name="$1" repo="$2"; shift 2
  say "$name: backup -> $repo"
  RESTIC_REPOSITORY="$repo" restic backup "${TARGETS[@]}" \
      --tag "$TAG" "$@" "${EXCLUDES[@]}"
  local rc=$?
  # restic exits 3 when some files were unreadable but the snapshot was still
  # written. That is a warning, not a failed backup — keep going and prune.
  if [[ $rc -ne 0 && $rc -ne 3 ]]; then
    echo "backup-ublion: $name backup FAILED (rc=$rc)" >&2; return $rc
  fi
  if [[ $rc -eq 3 ]]; then
    echo "backup-ublion: $name had unreadable files (rc=3) — snapshot was still written" >&2
    rc=0   # a warning, not a failed backup; see the note above
  fi

  # Dedup makes old snapshots nearly free, so keep generously but bounded.
  say "$name: forget/prune"
  RESTIC_REPOSITORY="$repo" restic forget --tag "$TAG" \
      --keep-daily 14 --keep-weekly 8 --keep-monthly 24 --prune >/dev/null \
      || echo "backup-ublion: $name prune failed" >&2
  RESTIC_REPOSITORY="$repo" restic snapshots --tag "$TAG" --latest 1
  return $rc
}

# restic returns 0 when only *some* of its targets are missing, quietly writing a
# snapshot without them. Verified on 0.18.1. So a renamed directory would vanish
# from every snapshot from that night on, with no error, until retention aged out
# the last one holding it. Fail loudly instead.
for t in "${TARGETS[@]}"; do
  [[ -e "$t" ]] || die "backup target does not exist: $t"
done

overall=0
if [[ "$WHICH" == "local" || "$WHICH" == "both" ]]; then
  run_repo local "$RESTIC_REPO_LOCAL" || overall=1
fi
if [[ "$WHICH" == "drive" || "$WHICH" == "both" ]]; then
  # --pack-size 128 and capped connections are the Drive quota fix; they are
  # pointless overhead on a local disk, so only the Drive run gets them.
  run_repo drive "$RESTIC_REPO_DRIVE" --pack-size 128 -o rclone.connections=2 || overall=1
fi

[[ $PREDUMP_RC -ne 0 ]] && overall=1
say "done (rc=$overall)"
exit $overall
