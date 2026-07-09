#!/bin/bash
#
# One-shot, idempotent migration of stray $HOME dotfiles/dirs into XDG
# locations. Only needed on machines that were already populated before the
# XDG env vars (in exports.sh) were added — a fresh install writes to the XDG
# paths from the start, so nothing to migrate there.
#
# Safe to re-run: each entry is skipped if the source is gone or the
# destination already exists. Nothing is hard-deleted (except an empty
# ~/.bundle) — stale copies go to the Trash (~/.Trash, 30-day recovery).
#
# pyenv can't be moved (compiled interpreters hardcode absolute paths), so it's
# reinstalled at the XDG root by scripts/install-pyenv.sh, then the old ~/.pyenv
# is trashed below once the new root exists.
#
# Deliberately NOT migrated: gsutil, wget hsts.

: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"

move() {
    local src="$1" dst="$2"
    [ -e "$src" ] || { echo "skip (no source):      ${src/#$HOME/~}"; return; }
    if [ -e "$dst" ]; then echo "skip (dest exists):    ${dst/#$HOME/~}"; return; fi
    mkdir -p "$(dirname "$dst")"
    mv "$src" "$dst" && echo "moved: ${src/#$HOME/~} -> ${dst/#$HOME/~}"
}

# Send a stale copy to the Trash instead of rm — recoverable for 30 days, and
# it tells you what it took. De-collides on name so re-runs don't clobber.
# ponytail: macOS ~/.Trash; on Linux the leftovers below don't exist so this
# never fires — wire in gio trash / trash-cli here if that ever changes.
trash() {
    local src="$1" base dst n=2
    [ -e "$src" ] || { echo "skip (no source):      ${src/#$HOME/~}"; return; }
    base="$(basename "$src")"; dst="$HOME/.Trash/$base"
    while [ -e "$dst" ]; do dst="$HOME/.Trash/${base}-${n}"; n=$((n + 1)); done
    mkdir -p "$HOME/.Trash"
    mv "$src" "$dst" && echo "trashed: ${src/#$HOME/~} -> ~/.Trash/${dst##*/}"
}

move "$HOME/.npm"        "$XDG_CACHE_HOME/npm"
move "$HOME/.docker"     "$XDG_CONFIG_HOME/docker"
move "$HOME/.ipython"    "$XDG_CONFIG_HOME/ipython"
move "$HOME/.jupyter"    "$XDG_CONFIG_HOME/jupyter"
move "$HOME/.matplotlib" "$XDG_CONFIG_HOME/matplotlib"
move "$HOME/.boto"       "$XDG_CONFIG_HOME/gcloud/boto"
move "$HOME/.ansible"    "$XDG_DATA_HOME/ansible"
move "$HOME/.lesshst"    "$XDG_STATE_HOME/less/history"
move "$HOME/.z"          "$XDG_DATA_HOME/zsh-z/data"
move "$HOME/.gitconfig"  "$XDG_CONFIG_HOME/git/config"  # git reads this path natively
move "$HOME/.cups"       "$XDG_CONFIG_HOME/cups"         # CUPS reads $XDG_CONFIG_HOME/cups (OpenPrinting/cups#10)
move "$HOME/.zhistory"   "$XDG_STATE_HOME/zsh/history"  # HISTFILE set to match in .zshrc
move "$HOME/.python_history" "$XDG_STATE_HOME/python/history"  # PYTHONSTARTUP shim reads this (pre-3.13)
move "$HOME/.local/pipx" "$XDG_DATA_HOME/pipx"          # then run: pipx reinstall-all (fixes baked venv paths)

# Stale $HOME copies already superseded by repo-managed XDG configs — the
# active versions live at the XDG paths, so these are dead weight. Trash them.
trash "$HOME/.p10k.zsh"                              # -> $XDG_CONFIG_HOME/zsh/.p10k.zsh (sourced in .zshrc)
for f in "$HOME"/.zcompdump*; do trash "$f"; done   # -> $XDG_CACHE_HOME/zsh/zcompdump-* (regenerated)
trash "$HOME/.zhistory"                             # -> $XDG_STATE_HOME/zsh/history (may reappear until old shells close)
trash "$HOME/.viminfo"                              # -> $XDG_STATE_HOME/vim/viminfo (viminfofile set in vim/vimrc)
trash "$HOME/.wget-hsts"                            # -> $XDG_STATE_HOME/wget/hsts (hsts-file set in wget/wgetrc via WGETRC)

# pyenv: only safe to drop the old ~/.pyenv once install-pyenv.sh has seeded the
# new XDG root — guard on it so re-running this before the reinstall never nukes
# the only copy of your interpreters. Old globals (incl. editable installs tied
# to local repos) are intentionally not carried over; recreate per-project.
_pyenv_new="${PYENV_ROOT:-$XDG_DATA_HOME/pyenv}"
if [ "$_pyenv_new" != "$HOME/.pyenv" ] && [ -n "$(ls -A "$_pyenv_new/versions" 2>/dev/null)" ]; then
    trash "$HOME/.pyenv"
elif [ -d "$HOME/.pyenv" ]; then
    echo "skip (new root empty):  ~/.pyenv  — run scripts/install-pyenv.sh first"
fi
unset _pyenv_new

# .bundle is empty on this machine — bundler recreates it at the XDG paths.
if [ -d "$HOME/.bundle" ] && [ -z "$(ls -A "$HOME/.bundle" 2>/dev/null)" ]; then
    rmdir "$HOME/.bundle" && echo "removed empty:         ~/.bundle"
fi

echo "xdg-migrate: done."
