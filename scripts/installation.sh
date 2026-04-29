#!/bin/bash

# This script bootstraps a machine from this dotfiles repo.
# On macOS: installs Homebrew (if missing), applies macOS defaults, installs
# packages from the Brewfile. On both platforms: installs zsh, zinit, stow,
# rust + rust CLIs, fzf, stows the backups/ tree to $HOME, and creates
# ~/.machine.sh for machine-specific config.

# Source the variables file (derive its location so the repo works anywhere)
_install_self="$(readlink -f "${BASH_SOURCE[0]}")"
source "$(dirname "$_install_self")/exports.sh"
unset _install_self

# Source the utility functions file
source $UTILS_F

# Ensure the repos directory exists
mkdir -p $REPO_DIR
mkdir -p $LOCAL_DIR

# Add all executables in .local/bin to the PATH
export PATH="$PATH:$LOCAL_DIR/bin"

# macOS: ensure Homebrew, apply defaults, restore packages from the Brewfile
if [[ "$OSTYPE" == "darwin"* ]]; then
    if ! command -v brew &>/dev/null; then
        echo "Homebrew not found. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # applies dock/finder/textedit defaults — defined in darwin/scripts.sh,
    # which is sourced transitively by DARWIN_SETTING_F
    source $DARWIN_SETTING_F
    mac_defaults

    brew bundle install --file=$BACKUP_DIR/.config/darwin/Brewfile
fi

# Linux (Debian/Ubuntu): install the same shell-experience packages via apt that
# the Brewfile installs on macOS. Skipped on other distros — extend as needed.
if [[ "$OSTYPE" == "linux-gnu"* ]] && command -v apt-get &>/dev/null; then
    echo "Installing Linux packages via apt..."
    sudo apt-get update
    # Hard requirements — install fails if any of these are missing.
    sudo apt-get install -y \
        zsh stow \
        build-essential ca-certificates curl wget \
        git gnupg gh \
        ripgrep jq tree htop ncdu \
        tmux fzf \
        python3 python3-pip python3-venv pipx \
        xclip \
        bat lsd zoxide
    # Nice-to-haves — install best-effort, one at a time so a missing package
    # in the user's repos (e.g. mc on some distros) doesn't fail the whole step.
    for pkg in mc wireguard-tools ffmpeg; do
        sudo apt-get install -y "$pkg" || echo "warn: skipped $pkg (not available)"
    done
    # Debian/Ubuntu ships bat as `batcat` to avoid a name clash. Expose it as
    # `bat` so the .aliases check (`command -v bat`) and downstream tools work.
    if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
        mkdir -p "$LOCAL_DIR/bin"
        ln -sf "$(command -v batcat)" "$LOCAL_DIR/bin/bat"
    fi
    # thefuck ships on PyPI; pipx gives an isolated install on PATH.
    if ! command -v thefuck &>/dev/null; then
        pipx ensurepath >/dev/null 2>&1 || true
        pipx install thefuck || echo "warn: thefuck install failed; continuing"
    fi
fi

# Install Zsh if still missing (e.g. non-apt Linux, or apt step skipped)
if ! command -v zsh &>/dev/null; then
    echo "Zsh not found. Installing..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Zsh not found, installing from source"
        install_zsh
        echo "Zsh installed, please restart your terminal."
        exit 0
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install zsh
    fi
fi


# Install zinit
if [ ! -d ~/.zinit ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/zdharma-continuum/zinit/main/scripts/install.sh)"
else
    echo "zinit already installed."
fi

# Copy dotfiles from $DOTFILES_DIR to $HOME using symbolic links
install_gnustow
stow_restore

# install rust if not installed
install_rust
install_rust_plugins

# install fzf (skipped if apt already provided it on Linux)
install_fzf

# install MesloLGS NF so Powerlevel10k's prompt glyphs render
install_nerd_font

# Create the machine source file if not present
if [ ! -f "$MACHINE_SOURCE" ]; then
    touch "$MACHINE_SOURCE"
fi

echo "Installation and setup complete. Please restart your terminal."
