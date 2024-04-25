# Dotfiles Repository

This repository contains configuration files and scripts for setting up a UNIX-like environment using dotfiles managed through GNU Stow.


## Installation

Clone this repository into your home directory:

```bash
cd $HOME
git clone https://your-repo-url/dotfiles.git
```

After cloning, navigate into the `dotfiles` directory and run the installation script:

```bash
cd dotfiles
bash scripts/installation.sh
```

This script performs the following actions:

- Checks for Zsh installation and installs if missing.
- Installs Oh My Zsh if it's not already installed.
- Downloads and sets up various Zsh plugins.
- Installs the Powerlevel10k theme.
- Restores previous stow configurations if any.
- Creates a `.machine.sh` file in your home directory for machine-specific configurations.

## Utilities

Additional utility commands are defined in `scripts/utils.sh`. This includes various installations and helper functions such as `install_chruby` for setting up Ruby environments, and `install_rust` for Rust programming language tools.

### Restoring Dotfiles

To reset your dotfiles to their original versions, use the `stow_restore` command found in `scripts/utils.sh`:

```bash
stow_restore
```

## Configuration Variables

Configuration paths and variables are set in `scripts/variables.sh`. Modify this file to customize the paths used by the scripts.

## Machine-Specific Settings

The scripts create a `.machine.sh` file in the home directory, which is sourced in `.zshrc`. Use this file to specify settings unique to the current machine.

## OS-Specific Settings

OS-specific settings for Zsh are located in the `backups/zsh` directory:

- `darwin_settings.zsh` for macOS.
- `linux_settings.zsh` for Linux.

