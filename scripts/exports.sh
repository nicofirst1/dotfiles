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
export UTILS_F="$SCRIPTS_DIR/utils.sh"       # Path to utility functions file
export EXPORTS_F="$SCRIPTS_DIR/exports.sh"     # Path to exports file
export ALIASES_F="$CONFIG_DIR/.aliases"       # Path to Zsh aliases file

# machine dependent
export DARWIN_SETTING_F="$CONFIG_DIR/zsh/darwin_settings.zsh"       # Path to macOS-specific Zsh settings file
export LINUX_SETTING_F="$CONFIG_DIR/zsh/linux_settings.zsh"       # Path to Linux-specific Zsh settings file

# Oh-My-Zsh setup
export ZSH="$HOME/.oh-my-zsh"       # Path to Oh-My-Zsh installation directory
export ZSH_CUSTOM="$ZSH/custom"       # Path to Oh-My-Zsh custom directory



# RUST SETUP
export RUSTUP_HOME="$LOCAL_DIR/rustup"       # Path to Rustup installation directory
export CARGO_HOME="$LOCAL_DIR/cargo"       # Path to Cargo installation directory


# path exports
export PATH="$PATH:$LOCAL_DIR/bin" # local bin
export PATH="$PATH:$CARGO_HOME/bin" # cargo bin
