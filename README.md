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
- Installs zinit if it's not already installed.
- Loads Zsh plugins and the Powerlevel10k theme via zinit.
- Restores previous stow configurations if any.
- Creates a `.machine.sh` file in your home directory for machine-specific configurations.

## Utilities

Additional utility commands are defined in `scripts/functions.sh`. This includes various installations and helper functions such as `install_chruby` for setting up Ruby environments, and `install_rust` for Rust programming language tools.

### Restoring Dotfiles

To reset your dotfiles to their original versions, use the `stow_restore` command found in `scripts/functions.sh`:

```bash
stow_restore
```

## Configuration Variables

Configuration paths and variables are set in `scripts/exports.sh`. Modify this file to customize the paths used by the scripts.

### Shell startup: `.zshenv` vs `.zshrc`

Environment variables live in `backups/.zshenv`, which zsh sources on **every**
invocation (interactive shells, scripts, and non-interactive subprocesses).
This is what makes tools spawned outside an interactive shell — `npm`, `git`,
`cargo` — honor the XDG redirects instead of littering `$HOME`. `.zshenv`
derives `DOTFILES_DIR` and sources `exports.sh`.

`backups/.zshrc` is **interactive-only**: prompt, plugins, aliases, and
completions. Don't put `export`s there — non-interactive shells never read it.

Tools are pointed at [XDG base directories](https://specifications.freedesktop.org/basedir-spec/latest/)
(`$XDG_CONFIG_HOME`, `$XDG_DATA_HOME`, etc.) in `exports.sh`. Machines populated
before these redirects existed can relocate stray dotfiles with the idempotent
`scripts/xdg-migrate.sh`. Run `xdg-ninja` (in `~/repos/libraries/xdg-ninja`) to
audit `$HOME` for files that still belong under XDG paths.

## Machine-Specific Settings

The scripts create a `.machine.sh` file in the home directory, which is sourced in `.zshrc`. Use this file to specify settings unique to the current machine.

## OS-Specific Settings

OS-specific settings for Zsh are located in `backups/.config/`:

- `backups/.config/darwin/settings` for macOS.
- `backups/.config/zsh/linux_settings.zsh` for Linux.

