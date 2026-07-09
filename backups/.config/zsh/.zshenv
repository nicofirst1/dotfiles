# .zshenv — real environment config, under $ZDOTDIR ($XDG_CONFIG_HOME/zsh).
# Loaded via the minimal $HOME/.zshenv stub, which sets ZDOTDIR then sources
# this. Runs on EVERY zsh invocation (interactive, non-interactive, scripts,
# subshells), so environment variables belong here, NOT in .zshrc, and tools
# spawned outside an interactive shell (npm, git, cargo…) still see the XDG
# redirects. Interactive-only setup (prompt, plugins, aliases) stays in .zshrc.
# Load order: https://zsh.sourceforge.io/Intro/intro_3.html

# Derive DOTFILES_DIR from this file's resolved (stow symlink) location — four
# dirs up from backups/.config/zsh/.zshenv. Normally already exported by the
# stub/exports.sh; this guard only fires if this file is sourced standalone.
if [[ -z "$DOTFILES_DIR" ]]; then
    export DOTFILES_DIR="${${(%):-%x}:A:h:h:h:h}"
fi

source "$DOTFILES_DIR/scripts/exports.sh"

# Rust/cargo env (adds $CARGO_HOME/bin to PATH; deduped by `typeset -U path`).
[[ -f "$CARGO_HOME/env" ]] && . "$CARGO_HOME/env"
