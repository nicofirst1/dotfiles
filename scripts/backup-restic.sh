#!/usr/bin/env bash
#
# backup-restic.sh  —  encrypted, deduplicated backup of the HEAVY agent data
#                      (Claude Code + Hermes sessions/transcripts/state +
#                      OpenObserve OTEL telemetry) to Drive.
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

# Google Drive rate-limits hard on bursts of small uploads (worse via rclone's
# shared API client). Stay under the per-minute quota: gentle drive pacing here,
# plus fewer+bigger packs and limited connections on the backup call below.
export RCLONE_DRIVE_PACER_MIN_SLEEP="${RCLONE_DRIVE_PACER_MIN_SLEEP:-200ms}"
export RCLONE_DRIVE_PACER_BURST="${RCLONE_DRIVE_PACER_BURST:-1}"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/claude}"
HERMES_HOME="${HERMES_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hermes}"
AGENTMEMORY="${AGENTMEMORY_HOME:-$HOME/.agentmemory}"
OPENOBSERVE_DIR="${OO_DATA_DIR:-$HOME/.local/share/openobserve}"
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
    # OpenObserve's metadata index (which streams/parquet files exist, schemas,
    # users) is a live WAL-mode sqlite; a torn read there orphans the parquet
    # data, so stage a consistent .backup and exclude the live file below.
    OO_META="$OPENOBSERVE_DIR/db/metadata.sqlite"
    if [[ -e "$OO_META" ]]; then
        mkdir -p "$STAGING/openobserve/db"
        sqlite3 "$OO_META" ".backup '$STAGING/openobserve/db/metadata.sqlite'" 2>/dev/null \
            || cp "$OO_META" "$STAGING/openobserve/db/metadata.sqlite"
    fi
fi

# 2. The backup. Include the precious trees + staged DBs; exclude everything
#    reinstallable (plugins, the hermes-agent codebase, bins) or regenerable
#    (caches, logs, live DBs — staged copies are backed up instead).
# ponytail: .agentmemory is backed up live (worker keeps writing). Safe because
#   it's event-sourced — stream_store is append-only (torn tail is recoverable),
#   state_store is a derived index rebuildable from the streams. If a guaranteed-
#   consistent snapshot is ever needed, pause com.nbrandizzi.agentmemory (or
#   `iii trigger` a checkpoint) around this call.
# ponytail: OpenObserve stream data (parquet) is immutable once flushed, so it
#   dedups near-free across days; the wal/ tail is backed up live and OpenObserve
#   replays it on restore. mmdb (75 MB GeoIP) and cache/tmp are re-downloadable/
#   regenerable, so they're excluded. The metadata sqlite goes in via staging.
restic backup "$CLAUDE_DIR" "$HERMES_HOME" "$AGENTMEMORY" "$OPENOBSERVE_DIR" "$STAGING" \
    --tag claude-hermes \
    --pack-size 128 \
    -o rclone.connections=2 \
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
    --exclude "$AGENTMEMORY/bin" \
    --exclude "$AGENTMEMORY/data.bak-*" \
    --exclude "$AGENTMEMORY/backups" \
    --exclude "$AGENTMEMORY/*.log" \
    --exclude "$AGENTMEMORY/*.pid" \
    --exclude "$AGENTMEMORY/.env.bak.*" \
    --exclude "$AGENTMEMORY/.env.pre-litellm.*" \
    --exclude "$OPENOBSERVE_DIR/cache" \
    --exclude "$OPENOBSERVE_DIR/tmp" \
    --exclude "$OPENOBSERVE_DIR/mmdb" \
    --exclude "$OPENOBSERVE_DIR/db/metadata.sqlite" \
    --exclude "$OPENOBSERVE_DIR/db/metadata.sqlite-wal" \
    --exclude "$OPENOBSERVE_DIR/db/metadata.sqlite-shm" \
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
