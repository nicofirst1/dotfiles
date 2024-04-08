#!/bin/bash

# Set up directories
HOME_DIR="$HOME"
REPO_DIR="$HOME_DIR/repos"
DOTFILES_DIR="$HOME_DIR/dotfiles"

# Ensure the repos directory exists
mkdir -p "$REPO_DIR"

# Install Zsh if not installed
if ! command -v zsh &> /dev/null; then
    echo "Zsh not found. Installing..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Zsh not found and cannot be installed without sudo privileges."
        echo "Please install Zsh manually if you wish to continue."
        exit 1
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install zsh
    fi
fi

# Download Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    echo "Oh My Zsh already installed."
fi


# Plugins
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/junegunn/fzf.git ~/$REPO_DIR/fzf-git
~/$REPO_DIR/fzf-git/install --all



# OS-specific installations
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Linux OS detected. Adjusting installations."

    cd $REPO_DIR
    # Download chruby
    wget https://github.com/postmodern/chruby/releases/download/v0.3.9/chruby-0.3.9.tar.gz
    tar -xzvf chruby-0.3.9.tar.gz
    cd chruby-0.3.9/
    make install PREFIX=$REPO_DIR/chruby




elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macOS detected. Installing brew dependencies."
    
    # Install Homebrew if not installed
    if ! command -v brew &> /dev/null; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Install dependencies with Homebrew
    brew install chruby ruby-install autojump

    # Setup Ruby
    ruby-install ruby
    chruby ruby
fi


# Sync dotfiles by creating symbolic links
# Example for .zshrc, extend this block for other dotfiles as needed
for file in $DOTFILES_DIR/*; do
    filename=$(basename "$file")
    target="$HOME_DIR/$filename"
    if [ -e "$target" ]; then
        echo "$target exists, skipping..."
    else
        ln -s "$file" "$target"
        echo "Linked $file to $target"
    fi
done


echo "Installation and setup complete. Please restart your terminal."
