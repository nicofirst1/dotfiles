#!/usr/bin/env bash
#
# install-restic-backup.sh  —  provision the restic backup of heavy agent data.
#
# NOT called by installation.sh (same policy as the other install-*.sh): depends
# on a configured rclone `gdrive:` remote and creates a secret. Run by hand:
#
#     bash ~/dotfiles/scripts/install-restic-backup.sh
#
# What it does:
#   1. install restic (brew)                        — the backup engine
#   2. preflight: rclone + gdrive: remote reachable
#   3. generate the repo password -> ~/.config/restic/password (0600, LOCAL only,
#      never in the dotfiles repo). You must copy it into your password manager —
#      lose it and the backup is unrecoverable ciphertext.
#   4. restic init (idempotent — skips if the repo already exists)
#   5. stow + load the daily LaunchAgent
#
# Idempotent: re-running keeps the existing password/repo and just re-validates.

set -euo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SELF/.." && pwd)"

LABEL="com.nbrandizzi.restic-backup"
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-rclone:gdrive:backups/claude-hermes-restic}"
PASS_FILE="$HOME/.config/restic/password"
export RESTIC_PASSWORD_FILE="$PASS_FILE"
LOG_DIR="$HOME/Library/Logs/restic"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
agent_loaded() { launchctl list 2>/dev/null | awk -v l="$1" '$3==l{f=1} END{exit f?0:1}'; }

[[ "$OSTYPE" == darwin* ]] || die "macOS only (uses launchctl)."

# --- 1. restic -------------------------------------------------------------
if command -v restic >/dev/null 2>&1; then
    say "restic present ($(restic version | head -1))."
else
    command -v brew >/dev/null || die "brew missing — install restic manually."
    say "Installing restic via brew..."
    brew install restic || die "brew install restic failed."
fi

# --- 2. preflight: rclone + gdrive remote ----------------------------------
command -v rclone >/dev/null || die "rclone missing — needed for the gdrive backend."
rclone listremotes 2>/dev/null | grep -qx "gdrive:" || die "rclone remote 'gdrive:' not configured. Run 'rclone config' first."
say "Probing gdrive: remote..."
rclone about gdrive: >/dev/null 2>&1 || warn "gdrive: didn't respond to 'about' — continuing, but the repo write may fail."

# --- 3. password file ------------------------------------------------------
mkdir -p "$(dirname "$PASS_FILE")"
if [[ -s "$PASS_FILE" ]]; then
    say "Password file already exists — keeping it ($PASS_FILE)."
    NEW_PASS=0
else
    say "Generating a repo password -> $PASS_FILE"
    umask 077
    openssl rand -base64 32 > "$PASS_FILE"
    chmod 600 "$PASS_FILE"
    NEW_PASS=1
fi

# --- 4. restic init (idempotent) -------------------------------------------
if restic cat config >/dev/null 2>&1; then
    say "restic repo already initialized at $RESTIC_REPOSITORY."
else
    say "Initializing restic repo at $RESTIC_REPOSITORY..."
    restic init || die "restic init failed (check gdrive: and the password file)."
fi

# --- 5. LaunchAgent --------------------------------------------------------
mkdir -p "$LOG_DIR"
command -v stow >/dev/null && { say "Stowing launchagents..."; stow --dir="$DOTFILES_DIR" --target="$HOME" --restow launchagents; } \
    || warn "stow not found — link the plist by hand."

TARGET="$HOME/Library/LaunchAgents/$LABEL.plist"
if agent_loaded "$LABEL"; then
    say "Backup agent already loaded — rebooting it to pick up changes..."
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$TARGET" 2>/dev/null || warn "re-bootstrap failed."
elif [[ -e "$TARGET" ]]; then
    say "Loading $LABEL..."
    launchctl bootstrap "gui/$(id -u)" "$TARGET" 2>/dev/null || warn "could not bootstrap (loads next login)."
else
    warn "plist not found at $TARGET — stow did not link it."
fi

# --- done ------------------------------------------------------------------
say "restic backup provisioned."
echo "  repo   : $RESTIC_REPOSITORY"
echo "  agent  : $LABEL (daily 04:00)"
echo "  logs   : $LOG_DIR/restic.{stdout,stderr}.log"
echo "  run now: bash $SELF/backup-restic.sh"
if [[ "${NEW_PASS:-0}" == 1 ]]; then
    echo
    warn "SAVE THE PASSWORD to your password manager NOW — it is not printed here."
    warn "Reveal it yourself with:   ! cat $PASS_FILE"
    warn "Without it, the encrypted backup on Drive is unrecoverable."
fi
