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
    # Hard requirements — install fails if any of these are missing. Mirrors
    # the set of CLI tools the macOS Brewfile installs that are needed for the
    # core shell experience (zinit + p10k + .aliases assumptions).
    sudo apt-get install -y \
        zsh stow \
        build-essential ca-certificates curl wget \
        git git-lfs git-delta gnupg gh \
        ripgrep jq tree htop ncdu \
        tmux fzf \
        python3 python3-pip python3-venv pipx \
        xclip \
        bat lsd zoxide \
        nodejs sshpass
    # Nice-to-haves — install best-effort, one at a time so a missing package
    # in the user's repos (e.g. mc on some distros) doesn't fail the whole step.
    for pkg in mc wireguard-tools ffmpeg autojump cowsay fortune-mod lolcat glab yarnpkg; do
        sudo apt-get install -y "$pkg" || echo "warn: skipped $pkg (not available)"
    done
    # Debian/Ubuntu renames a couple of binaries to avoid clashes; symlink
    # them back to the names everyone expects so .aliases and downstream tools
    # work the same as on the macOS side.
    mkdir -p "$LOCAL_DIR/bin"
    if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
        ln -sf "$(command -v batcat)" "$LOCAL_DIR/bin/bat"
    fi
    if command -v yarnpkg &>/dev/null && ! command -v yarn &>/dev/null; then
        ln -sf "$(command -v yarnpkg)" "$LOCAL_DIR/bin/yarn"
    fi
    # PyPI tools via pipx — isolated venvs that drop binaries on PATH.
    pipx ensurepath >/dev/null 2>&1 || true
    if ! command -v thefuck &>/dev/null; then
        pipx install thefuck || echo "warn: thefuck install failed; continuing"
    fi
    if ! command -v uv &>/dev/null; then
        pipx install uv || echo "warn: uv install failed; continuing"
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

# tmux + oh-my-tmux: tmux gives us pane splits (Ptyxis can't), and the
# config drives 'prefix |' / 'prefix -' bindings used on both platforms.
install_tmux

# Ptyxis (GNOME terminal): match the iTerm2 profile — Catppuccin Macchiato
# palette + MesloLGS NF font so colors and Powerlevel10k glyphs line up with
# the macOS setup. Also launch tmux on each new tab/window so Ctrl+Shift+T
# drops straight into a tmux session (where pane splits live). No-op if
# Ptyxis or gsettings isn't on the box.
if [[ "$OSTYPE" == "linux-gnu"* ]] && command -v ptyxis &>/dev/null && command -v gsettings &>/dev/null; then
    PTYXIS_PROFILE_UUID="$(gsettings get org.gnome.Ptyxis default-profile-uuid 2>/dev/null | tr -d \')"
    if [ -n "$PTYXIS_PROFILE_UUID" ]; then
        PTYXIS_PROFILE_PATH="/org/gnome/Ptyxis/Profiles/$PTYXIS_PROFILE_UUID/"
        gsettings set org.gnome.Ptyxis.Profile:"$PTYXIS_PROFILE_PATH" palette 'Catppuccin Macchiato' || true
        gsettings set org.gnome.Ptyxis font-name 'MesloLGS NF 13' || true
        gsettings set org.gnome.Ptyxis use-system-font false || true
        # Start each new Ptyxis tab/window inside its own tmux session so
        # `prefix |` / `prefix -` splits work out of the box. Each tab is
        # an independent session — splits live inside the tab.
        gsettings set org.gnome.Ptyxis.Profile:"$PTYXIS_PROFILE_PATH" custom-command 'tmux' || true
        gsettings set org.gnome.Ptyxis.Profile:"$PTYXIS_PROFILE_PATH" use-custom-command true || true
        # Close-tab on Ctrl+W to match the iTerm Cmd+W muscle memory.
        # Trade-off: zsh's ^W (backward-kill-word) is now intercepted by
        # Ptyxis — Alt+Backspace (bound in linux_settings.zsh) replaces it.
        gsettings set org.gnome.Ptyxis.Shortcuts close-tab '<ctrl>w' || true
        echo "Ptyxis: applied Catppuccin Macchiato palette + MesloLGS NF 13 font + tmux launcher + Ctrl+W close-tab"
    fi
fi

# Create the machine source file if not present
if [ ! -f "$MACHINE_SOURCE" ]; then
    touch "$MACHINE_SOURCE"
fi

echo "Installation and setup complete. Please restart your terminal."
