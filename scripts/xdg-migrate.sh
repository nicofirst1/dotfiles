#!/bin/bash
#
# One-shot, idempotent migration of stray $HOME dotfiles/dirs into XDG
# locations. Only needed on machines that were already populated before the
# XDG env vars (in exports.sh) were added — a fresh install writes to the XDG
# paths from the start, so nothing to migrate there.
#
# Safe to re-run: each entry is skipped if the source is gone or the
# destination already exists. Nothing is deleted (except an empty ~/.bundle).
#
# Deliberately NOT migrated: pyenv (~/.pyenv, multi-GB, conventional path),
# pipx (~/.local/pipx, venvs with baked-in absolute paths), gsutil, wget hsts,
# python_history (needs Python 3.13+ for a clean relocation).

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

# .bundle is empty on this machine — bundler recreates it at the XDG paths.
if [ -d "$HOME/.bundle" ] && [ -z "$(ls -A "$HOME/.bundle" 2>/dev/null)" ]; then
    rmdir "$HOME/.bundle" && echo "removed empty:         ~/.bundle"
fi

echo "xdg-migrate: done."
