#!/usr/bin/env bash
#
# backup-restic.sh  —  encrypted, deduplicated backup of the HEAVY agent data
#                      (Claude Code + Hermes sessions/transcripts/state) to Drive.
#
# Companion to snapshot-memories.sh: memories (~330 KB) go to git; this handles
# the ~1.4 GB of session transcripts and live DB state that must NOT go in git
# (binary/huge/secret) but that we never want to lose. restic gives encryption,
# cross-session dedup, incremental snapshots, and point-in-time restore; the
# backend is the existing rclone `gdrive:` remote.
#
# Run by hand or via the com.nbrandizzi.restic-backup LaunchAgent (daily).
# Provisioned by install-restic-backup.sh (installs restic, writes the password
# file, inits the repo, loads the agent).

set -euo pipefail

# Machine-specific repo location lives in a LOCAL env file (dotfiles is public),
# written by install-restic-backup.sh. It pins the repo to a Drive folder by ID
# (RCLONE_DRIVE_ROOT_FOLDER_ID) so rclone stays at drive.file scope — the backup
# can only touch its own folder, never the rest of the Drive.
RESTIC_ENV="${RESTIC_ENV:-$HOME/.config/restic/env}"
# shellcheck source=/dev/null
[[ -f "$RESTIC_ENV" ]] && source "$RESTIC_ENV"

export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-rclone:gdrive:}"
export RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-$HOME/.config/restic/password}"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/claude}"
HERMES_HOME="${HERMES_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hermes}"
STAGING="$HOME/.config/restic/staging"

die() { printf 'backup-restic: %s\n' "$*" >&2; exit 1; }

command -v restic >/dev/null 2>&1 || die "restic missing — run install-restic-backup.sh"
command -v rclone >/dev/null 2>&1 || die "rclone missing — needed for the gdrive backend"
[[ -f "$RESTIC_PASSWORD_FILE" ]] || die "no password file at $RESTIC_PASSWORD_FILE"

# 1. Consistent snapshots of live SQLite DBs (WAL-safe) into staging. Backing up
#    a live .db directly risks a torn read; sqlite's .backup gives a clean copy,
#    and an uncompressed .db dedups well across days (unchanged pages are shared).
rm -rf "$STAGING"; mkdir -p "$STAGING/hermes"
if command -v sqlite3 >/dev/null 2>&1; then
    for db in "$HERMES_HOME"/*.db; do
        [[ -e "$db" ]] || continue
        sqlite3 "$db" ".backup '$STAGING/hermes/$(basename "$db")'" 2>/dev/null \
            || cp "$db" "$STAGING/hermes/$(basename "$db")"   # fallback: best-effort copy
    done
fi

# 2. The backup. Include the precious trees + staged DBs; exclude everything
#    reinstallable (plugins, the hermes-agent codebase, bins) or regenerable
#    (caches, logs, live DBs — staged copies are backed up instead).
restic backup "$CLAUDE_DIR" "$HERMES_HOME" "$STAGING" \
    --tag claude-hermes \
    --exclude-caches \
    --exclude "$CLAUDE_DIR/plugins" \
    --exclude "$CLAUDE_DIR/paste-cache" \
    --exclude "$CLAUDE_DIR/cache" \
    --exclude "$HERMES_HOME/hermes-agent" \
    --exclude "$HERMES_HOME/bin" \
    --exclude "$HERMES_HOME/cache" \
    --exclude "$HERMES_HOME/logs" \
    --exclude "$HERMES_HOME/sandboxes" \
    --exclude "$HERMES_HOME/audio_cache" \
    --exclude "$HERMES_HOME/image_cache" \
    --exclude "$HERMES_HOME/models_dev_cache.json" \
    --exclude "$HERMES_HOME/*_cache.json" \
    --exclude "$HERMES_HOME/*.db" \
    --exclude "$HERMES_HOME/*.db-wal" \
    --exclude "$HERMES_HOME/*.db-shm" \
    --exclude "$HERMES_HOME/*.db-journal" \
    --exclude "**/.DS_Store" \
    --exclude "**/*.lock"

rm -rf "$STAGING"

# 3. Retention. Dedup makes old snapshots nearly free, so keep generously but
#    bounded (Claude Code auto-deletes sessions after ~30 days, so daily runs are
#    what actually preserve them). ponytail: keep-monthly 120 = ~10y ceiling.
restic forget --tag claude-hermes \
    --keep-daily 14 --keep-weekly 8 --keep-monthly 120 --prune

echo "== latest snapshot =="
restic snapshots --tag claude-hermes --latest 1
