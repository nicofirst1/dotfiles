# Set up directories
export REPO_DIR="$HOME/repos"       # Directory for storing repositories
export DOTFILES_DIR="$HOME/dotfiles"       # Directory for storing dotfiles
export SCRIPTS_DIR="$DOTFILES_DIR/scripts"       # Directory for storing scripts
export BACKUP_DIR="$DOTFILES_DIR/backups"       # Directory for storing backups
export MACHINE_SOURCE="$HOME/.machine.sh"       # Path to machine-specific configuration file
export CONFIG_DIR="$HOME/.config"       # Directory for storing configuration files
export LOCAL_DIR="$HOME/.local"       # Directory for storing local files

# Set up files
export ZSHRC_F="$HOME/.zshrc"       # Path to Zsh configuration file
export UTILS_F="$SCRIPTS_DIR/functions.sh"       # Path to utility functions file
export EXPORTS_F="$SCRIPTS_DIR/exports.sh"     # Path to exports file
export ALIASES_F="$CONFIG_DIR/.aliases"       # Path to Zsh aliases file

# machine dependent
export DARWIN_SETTING_D="$CONFIG_DIR/darwin"       # Path to macOS-specific Zsh settings file
export DARWIN_SETTING_F="$DARWIN_SETTING_D/settings"       # Path to macOS-specific Zsh settings file
export LINUX_SETTING_F="$CONFIG_DIR/zsh/linux_settings.zsh"       # Path to Linux-specific Zsh settings file

# Oh-My-Zsh setup
export ZSH="$HOME/.oh-my-zsh"       # Path to Oh-My-Zsh installation directory
export ZSH_CUSTOM="$ZSH/custom"       # Path to Oh-My-Zsh custom directory

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

# Oh-My-Zsh setup
export OMZSH_DIR="$HOME/.oh-my-zsh" # path to Oh-My-Zsh installation directory

# Zinit
export ZINIT_HOME="$LOCAL_DIR/share/zinit/zinit.git"

# path exports
export PATH="$PATH:$LOCAL_DIR/bin" # local bin
export PATH="$PATH:$LOCAL_DIR/lib" # local lib
export PATH="$PATH:$CARGO_HOME/bin" # cargo bin

# Poetry setup
export POETRY_VIRTUALENVS_IN_PROJECT=true


# disabling automatic widget re-binding?
# https://github.com/zsh-users/zsh-autosuggestions/issues/544#issuecomment-640094700
export ZSH_AUTOSUGGEST_MANUAL_REBIND=flase