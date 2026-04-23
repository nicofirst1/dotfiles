# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
### Fixed
### Changed
### Removed



## [v0.2.0] - 2026-04-23

### Added
- SwiftBar plugin `wg.5s.sh` — menu-bar indicator for WireGuard home tunnel (ifconfig-based detection, osascript admin-privileges toggle)
- `.aliases`: WireGuard `wgup`/`wgdown`/`wgstatus` aliases, `cd ...` chain shortcuts, `data-clean` alias for midnight-commander
- `python/settings.sh`: `py()` wrapping `uv run`
- `.zshrc`: opencode PATH, gcloud SDK init
- `installation.sh`: Homebrew bootstrap, unconditional `mac_defaults` on macOS, `brew bundle install` from the tracked Brewfile
- iTerm2 custom prefs folder setup in `mac_defaults` — plist loads from and writes to the stowed copy, so UI changes persist in the repo
### Fixed
- typo `flase` → `false` in `ZSH_AUTOSUGGEST_MANUAL_REBIND` export
- broken `PATH` line in `installation.sh` (`$$LOCAL_DIR` → `$LOCAL_DIR`)
- `mac_defaults` only ran when zsh was missing — now runs on every macOS bootstrap
- stale file references in README (`utils.sh`, `variables.sh`, `backups/zsh/`)
### Changed
- Brewfile synced as new-machine install spec (VSCode extensions removed, taps and formulae aligned with keep-list)
- README install steps reflect zinit (no longer mention Oh My Zsh)
### Removed
- Oh My Zsh scaffolding: `ZSH`/`ZSH_CUSTOM`/`OMZSH_DIR` exports, `ZSH_THEME`/`CASE_SENSITIVE` vars, `zsh_plugins()` function, OMZ + p10k install blocks in `installation.sh` (zinit handles plugins and theme)
- `wtp` hook from `.zshrc` and `satococoa/tap` from Brewfile



## [v0.1.0] - 2024-09-05

### Added
- Changelog
- python sourcing if present
- autoflake alias
- start_ssh_agent function
### Fixed
- autosuggestion now saving memory on cluster
- autosuggestion not showing on first command: removed wait
- slow zsh initialization, using agkozak implementation now
### Changed
### Removed
- source_if_exists function


