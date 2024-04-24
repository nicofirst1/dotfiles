#!/bin/bash
source $HOME/dotfiles/scripts/variables
source $DOTFILES_DIR/utils.sh

echo " DOTFILES_DIR: $DOTFILES_DIR"

# Ensure the repos directory exists
mkdir -p "$REPO_DIR"
mkdir -p "$HOME/.local"

# add to PATH all in .local/bin
export PATH="$PATH:$HOME/.local/bin"

# Install Zsh if not installed
if ! command -v zsh &>/dev/null; then
    echo "Zsh not found. Installing..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Zsh not found installing from source"
        echo "You can install it with the zsh_install command"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install zsh
    fi
fi



# Download Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]
then
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "Oh My Zsh already installed."
fi

# Plugins
zsh_plugins

#pip install --user --upgrade thefuck || pip3 install --user --upgrade thefuck


# Install Powerlevel10k theme
install_chruby 
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k


# STOW restore
stow_restore


# create the machine source file if not present
if [ ! -f "$MACHINE_SOURCE" ]; then
    touch "$MACHINE_SOURCE"
fi



echo "Installation and setup complete. Please restart your terminal."
