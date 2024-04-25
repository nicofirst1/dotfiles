# Set up directories
REPO_DIR="$HOME/repos"       # Directory for storing repositories
DOTFILES_DIR="$HOME/dotfiles"       # Directory for storing dotfiles
BACKUP_DIR="$DOTFILES_DIR/backups"       # Directory for storing backups
MACHINE_SOURCE="$HOME/.machine.sh"       # Path to machine-specific configuration file
CONFIG_DIR="$HOME/.config"       # Directory for storing configuration files
LOCAL_DIR="$HOME/.local"       # Directory for storing local files

# RUST SETUP
export RUSTUP_HOME="$LOCAL_DIR/rustup"       # Path to Rustup installation directory
export CARGO_HOME="$LOCAL_DIR/cargo"       # Path to Cargo installation directory
