#!/usr/bin/env bash
#
# install-hermes.sh  —  wire HERMES_HOME into the dotfiles / claude_memory repos
#
# NOT called by installation.sh on purpose (same policy as install-agentmemory.sh
# and install-litellm-router.sh): Hermes is installed separately and its data is
# machine-specific. Run it by hand after installing Hermes:
#
#     bash ~/dotfiles/scripts/install-hermes.sh
#     bash ~/dotfiles/scripts/install-hermes.sh --with-backup ~/Backups/hermes
#
# What it does — Hermes is monolithic + non-XDG: a single HERMES_HOME holds
# config, secrets, state.db, and data with no separate config/data env vars. This
# script makes the *durable* pieces reproducible by symlinking them back into git:
#
#   1. $HERMES_HOME/config.yaml -> config/hermes/config.yaml  (this repo)
#   2. $HERMES_HOME/memories    -> claude_memory/hermes/memories
#
# Everything else stays LOCAL by design: state.db (+ -wal/-shm) is a live sqlite
# DB that must never go in git (binary, unmergeable, corrupts on cloud-sync while
# open); sessions/ is a regenerated mirror of state.db; cache/logs are transient;
# .env/auth.json are secrets. For those, use Hermes' own WAL-safe backup instead
# of git — see --with-backup below, which registers a native `hermes cron` job
# running `hermes backup --quick` to a PRIVATE target (never the public dotfiles).
#
# Idempotent: re-running re-validates every link. A pre-existing real file/dir at
# a link path is backed up (files) or merged (empty/non-colliding dirs) before the
# symlink is made; a non-empty colliding dir is left untouched and reported.

set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SELF/.." && pwd)"

HERMES_HOME="${HERMES_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/hermes}"
CLAUDE_MEMORY_DIR="${CLAUDE_MEMORY_DIR:-$HOME/repos/personal/claude_memory}"
DISPLACED_DIR="$DOTFILES_DIR/backups/hermes-displaced"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# link SRC LINK — make LINK a symlink to SRC, safely and idempotently.
#   already correct symlink -> skip; wrong symlink -> repoint;
#   real file -> back up then link; empty real dir -> replace with link;
#   non-empty real dir -> move non-colliding contents into SRC then link,
#     or refuse if any name collides (never overwrites your data).
link() {
    local src="$1" link="$2"
    [[ -e "$src" ]] || die "source missing: $src (create/track it first)"
    mkdir -p "$(dirname "$link")"

    if [[ -L "$link" ]]; then
        if [[ "$(readlink "$link")" == "$src" ]]; then
            echo "  • ok: $link -> $src"
            return
        fi
        warn "repointing $link (was -> $(readlink "$link"))"
        ln -sfn "$src" "$link"; return
    fi

    if [[ -f "$link" ]]; then
        mkdir -p "$DISPLACED_DIR"
        local bak="$DISPLACED_DIR/$(basename "$link").$(date +%Y%m%d%H%M%S)"
        mv "$link" "$bak"
        warn "backed up existing file -> $bak"
        ln -s "$src" "$link"; echo "  • linked: $link -> $src"; return
    fi

    if [[ -d "$link" ]]; then
        # Merge real dir into the tracked source, then replace with a symlink.
        # Refuse on any name collision so nothing is silently overwritten.
        local f base collided=0
        shopt -s dotglob nullglob
        for f in "$link"/*; do
            base="$(basename "$f")"
            [[ -e "$src/$base" ]] && { warn "collision: $src/$base already exists"; collided=1; }
        done
        if (( collided )); then
            shopt -u dotglob nullglob
            warn "left $link untouched — merge it into $src by hand, then re-run."
            return
        fi
        for f in "$link"/*; do mv "$f" "$src/"; done
        shopt -u dotglob nullglob
        rmdir "$link"
        ln -s "$src" "$link"; echo "  • merged + linked: $link -> $src"; return
    fi

    ln -s "$src" "$link"; echo "  • linked: $link -> $src"
}

# --- preconditions ----------------------------------------------------------
command -v hermes >/dev/null 2>&1 || warn "hermes not on PATH — links still made; Hermes will pick them up on first run."
mkdir -p "$HERMES_HOME"

# --- 1 + 2. the durable symlinks --------------------------------------------
say "Wiring durable Hermes data into git..."
mkdir -p "$CLAUDE_MEMORY_DIR/hermes/memories"   # source of truth for memories
link "$DOTFILES_DIR/config/hermes/config.yaml" "$HERMES_HOME/config.yaml"
link "$CLAUDE_MEMORY_DIR/hermes/memories"       "$HERMES_HOME/memories"

# --- 3. opt-in: native backup cron for the local-only state -----------------
# state.db / secrets / sessions never go in git. --with-backup DIR schedules a
# daily WAL-safe `hermes backup --quick` into DIR (put DIR under your existing
# encrypted machine backup — restic/borg/cloud — NOT the public dotfiles repo).
if [[ "${1:-}" == "--with-backup" ]]; then
    BACKUP_TARGET="${2:?--with-backup needs a target directory}"
    command -v hermes >/dev/null 2>&1 || die "--with-backup needs hermes on PATH."
    mkdir -p "$BACKUP_TARGET"
    SCRIPTS="$HERMES_HOME/scripts"; mkdir -p "$SCRIPTS"
    cat > "$SCRIPTS/backup.sh" <<EOF
#!/usr/bin/env bash
# Generated by install-hermes.sh. WAL-safe snapshot of critical Hermes state.
set -euo pipefail
hermes backup --quick -l cron -o "$BACKUP_TARGET/hermes-\$(date +%Y%m%d).zip"
EOF
    chmod +x "$SCRIPTS/backup.sh"
    if hermes cron list 2>/dev/null | grep -q hermes-backup; then
        say "backup cron already registered — leaving it."
    else
        say "Registering daily backup cron (03:00) -> $BACKUP_TARGET"
        hermes cron create --no-agent --name hermes-backup '0 3 * * *' \
            --script backup.sh || warn "cron registration failed — register by hand."
    fi
fi

# --- done -------------------------------------------------------------------
say "Hermes wired. Durable data is in git; state.db/secrets/sessions stay local."
echo "  config  : $HERMES_HOME/config.yaml -> config/hermes/ (this repo)"
echo "  memories: $HERMES_HOME/memories    -> $CLAUDE_MEMORY_DIR/hermes/memories"
echo
echo "Back up local-only state (state.db, secrets) off-repo. One-shot:"
echo "  hermes backup --quick -o ~/Backups/hermes/hermes-\$(date +%Y%m%d).zip"
echo "Or schedule it:  bash $SELF/install-hermes.sh --with-backup ~/Backups/hermes"
