#!/bin/bash

# This script is used for installation and setup of dotfiles and related tools.
# It sets up the necessary environment variables, installs Zsh if not already installed,
# downloads Oh My Zsh, installs plugins, installs the Powerlevel10k theme,
# copies dotfiles to the home directory using symbolic links, and creates a machine source file if not present.

# Source the variables file
source $HOME/dotfiles/scripts/exports.sh

# Source the utility functions file
source $UTILS_F

# Ensure the repos directory exists
mkdir -p $REPO_DIR
mkdir -p $LOCAL_DIR

# Add all executables in .local/bin to the PATH
export PATH="$PATH:$$LOCAL_DIR/bin"

# Install Zsh if not installed
if ! command -v zsh &>/dev/null; then
    echo "Zsh not found. Installing..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Zsh not found installing from source"
        install_zsh
        echo "Zsh installed, please restart your terminal."
        exit 0
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install zsh
        mac_defaults
    fi
fi

# Download Oh My Zsh if not already installed
if [ ! -d $OMZSH_DIR ]; then
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "Oh My Zsh already installed."
fi

# Install Zsh plugins
zsh_plugins

# Install the Powerlevel10k theme
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"

# Copy dotfiles from $DOTFILES_DIR to $HOME using symbolic links
install_gnustow
stow_restore

# install rust if not installed
install_rust
install_rust_plugins

# install fzf
install_fzf

# Create the machine source file if not present
if [ ! -f "$MACHINE_SOURCE" ]; then
    touch "$MACHINE_SOURCE"
fi

echo "Installation and setup complete. Please restart your terminal."
