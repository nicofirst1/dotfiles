# .zshenv — sourced by EVERY zsh invocation (interactive, non-interactive,
# scripts, subshells). Environment variables belong here, NOT in .zshrc, so
# tools spawned outside an interactive shell (npm, git, cargo…) still see the
# XDG redirects. Interactive-only setup (prompt, plugins, aliases) stays in
# .zshrc. Load order: https://zsh.sourceforge.io/Intro/intro_3.html

# Derive DOTFILES_DIR from this file's resolved (stow symlink) location, so the
# repo can live anywhere without a hardcoded path.
if [[ -z "$DOTFILES_DIR" ]]; then
    export DOTFILES_DIR="${${(%):-%x}:A:h:h}"
fi

source "$DOTFILES_DIR/scripts/exports.sh"

# Rust/cargo env (adds $CARGO_HOME/bin to PATH; deduped by `typeset -U path`).
[[ -f "$CARGO_HOME/env" ]] && . "$CARGO_HOME/env"
