# Set up directories
export REPO_DIR="$HOME/repos"       # Directory for storing repositories

# DOTFILES_DIR: derived from this file's own location so the repo works wherever
# it's cloned. Honors a pre-set DOTFILES_DIR if the caller already exported one.
if [[ -z "$DOTFILES_DIR" ]]; then
    _exports_self="${BASH_SOURCE[0]:-${(%):-%x}}"
    if [[ -n "$ZSH_VERSION" ]]; then
        export DOTFILES_DIR="${_exports_self:A:h:h}"
    else
        export DOTFILES_DIR="$(cd "$(dirname "$(readlink -f "$_exports_self")")/.." && pwd)"
    fi
    unset _exports_self
fi
export SCRIPTS_DIR="$DOTFILES_DIR/scripts"       # Directory for storing scripts
export BACKUP_DIR="$DOTFILES_DIR/backups"       # Directory for storing backups
export CONFIG_DIR="$HOME/.config"       # Directory for storing configuration files
export LOCAL_DIR="$HOME/.local"       # Directory for storing local files

# Set up files
export ZSHRC_F="${ZDOTDIR:-$HOME}/.zshrc"       # Path to Zsh configuration file (under $ZDOTDIR)
export UTILS_F="$SCRIPTS_DIR/functions.sh"       # Path to utility functions file
export EXPORTS_F="$SCRIPTS_DIR/exports.sh"     # Path to exports file
export ALIASES_F="$CONFIG_DIR/.aliases"       # Path to Zsh aliases file

# machine dependent
export DARWIN_SETTING_D="$CONFIG_DIR/darwin"       # Path to macOS-specific Zsh settings file
export DARWIN_SETTING_F="$DARWIN_SETTING_D/settings"       # Path to macOS-specific Zsh settings file
export LINUX_SETTING_F="$CONFIG_DIR/zsh/linux_settings.zsh"       # Path to Linux-specific Zsh settings file

# Entr
export ENTR_DIR="$CONFIG_DIR/entr"       # Path to the entr repository
export ENTR_CONFIG="$ENTR_DIR/conf.sh"       # Path to the entr configuration file

# RUST SETUP
export RUSTUP_HOME="$LOCAL_DIR/rustup"       # Path to Rustup installation directory
export CARGO_HOME="$LOCAL_DIR/cargo"       # Path to Cargo installation directory


# Prefer US English and use UTF-8.
export LANG='en_US.UTF-8';
export LC_ALL='en_US.UTF-8';

# Set up XDG directories
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"

# Keep tools from littering $HOME — point them at XDG dirs. Existing data was
# relocated once by scripts/xdg-migrate.sh (idempotent; re-run on new machines).
export BUNDLE_USER_CONFIG="$XDG_CONFIG_HOME/bundle"
export BUNDLE_USER_CACHE="$XDG_CACHE_HOME/bundle"
export BUNDLE_USER_PLUGIN="$XDG_DATA_HOME/bundle"
export NPM_CONFIG_CACHE="$XDG_CACHE_HOME/npm"
export NPM_CONFIG_INIT_MODULE="$XDG_CONFIG_HOME/npm/config/npm-init.js"
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME/npm/npmrc"   # so a future ~/.npmrc lands in XDG
export DOCKER_CONFIG="$XDG_CONFIG_HOME/docker"
export IPYTHONDIR="$XDG_CONFIG_HOME/ipython"
export JUPYTER_CONFIG_DIR="$XDG_CONFIG_HOME/jupyter"
export MPLCONFIGDIR="$XDG_CONFIG_HOME/matplotlib"
export BOTO_CONFIG="$XDG_CONFIG_HOME/gcloud/boto"
export ANSIBLE_HOME="$XDG_DATA_HOME/ansible"
export LESSHISTFILE="$XDG_STATE_HOME/less/history"
export WGETRC="$XDG_CONFIG_HOME/wget/wgetrc"    # wgetrc redirects hsts-file to XDG (see backups/.config/wget/wgetrc)
export ZSHZ_DATA="$XDG_DATA_HOME/zsh-z/data"
export PIPX_HOME="$XDG_DATA_HOME/pipx"          # relocated via `pipx reinstall-all`; bin stays ~/.local/bin
export PYTHONSTARTUP="$XDG_CONFIG_HOME/python/pythonstartup.py"  # REPL history -> XDG (pre-3.13: no PYTHON_HISTORY)
# pyenv can't be moved in place (compiled interpreters hardcode absolute dylib
# install names + shebangs), so this is a reinstall-at-new-root, not a mv:
# scripts/install-pyenv.sh seeds the versions here; xdg-migrate.sh trashes the
# old ~/.pyenv once they exist.
export PYENV_ROOT="$XDG_DATA_HOME/pyenv"
# Claude Code: old ~/.claude copied (not moved) to $XDG_CONFIG_HOME/claude —
# verifying nothing still writes to the old path before trashing it.
export CLAUDE_CONFIG_DIR="$XDG_CONFIG_HOME/claude"

# Hermes Agent (NousResearch) is monolithic + non-XDG: a single HERMES_HOME
# holds config, secrets, AND data (memories/, sessions/, cache/, logs/) with no
# separate config/data env vars. Point it at XDG config; scripts/install-hermes.sh
# symlinks the durable memories/ into the claude_memory repo so it's versioned
# there, and keeps config.yaml stow-tracked from config/hermes/. Everything else
# stays local: sessions/ is a regenerated mirror of state.db (not durable), and
# cache/logs are transient. Secrets (.env, auth.json) stay local, never tracked.
export HERMES_HOME="$XDG_CONFIG_HOME/hermes"

# Zinit — installer layout varies: the canonical install.sh clones to
# share/zinit/zinit.git, but some installs end up nested as zinit.git/zinit.git.
# Prefer the nested layout if it exists, else fall back to the flat one.
if [[ -f "$LOCAL_DIR/share/zinit/zinit.git/zinit.git/zinit.zsh" ]]; then
    export ZINIT_HOME="$LOCAL_DIR/share/zinit/zinit.git/zinit.git"
else
    export ZINIT_HOME="$LOCAL_DIR/share/zinit/zinit.git"
fi

# path exports — `typeset -U` dedupes so sourcing this on every shell (via
# .zshenv) doesn't stack duplicate PATH entries. zsh-only; bash has no `path`.
[[ -n "$ZSH_VERSION" ]] && typeset -U path PATH
export PATH="$PATH:$LOCAL_DIR/bin" # local bin
export PATH="$PATH:$LOCAL_DIR/lib" # local lib
export PATH="$PATH:$CARGO_HOME/bin" # cargo bin

# Poetry setup
export POETRY_VIRTUALENVS_IN_PROJECT=true


# disabling automatic widget re-binding?
# https://github.com/zsh-users/zsh-autosuggestions/issues/544#issuecomment-640094700
export ZSH_AUTOSUGGEST_MANUAL_REBIND=false