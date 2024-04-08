#!/bin/bash

# Set up directories
REPO_DIR="$HOME/repos"
DOTFILES_DIR="$HOME/dotfiles"

source $DOTFILES_DIR/utils.sh

# Ensure the repos directory exists
mkdir -p "$REPO_DIR"

# Install Zsh if not installed
if ! command -v zsh &>/dev/null; then
    echo "Zsh not found. Installing..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Zsh not found and cannot be installed without sudo privileges."
        echo "Please install Zsh manually if you wish to continue."
        exit 1
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install zsh
    fi
fi

# check if python is available
check_python() install_mackup() if # install mackup
    # Download Oh My Zsh
    [ ! -d "$HOME/.oh-my-zsh" ]
then
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "Oh My Zsh already installed."
fi

# Plugins
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/junegunn/fzf.git ~/$REPO_DIR/fzf-git
~/$REPO_DIR/fzf-git/install --all

# Install Powerlevel10k theme
install_chruby() cp $DOTFILES_DIR/.mackup.cfg $HOME/.mackup.cfg

echo "Installation and setup complete. Please restart your terminal."
