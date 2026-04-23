# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
### Fixed
- typo `flase` → `false` in `ZSH_AUTOSUGGEST_MANUAL_REBIND` export
- broken `PATH` line in `installation.sh` (`$$LOCAL_DIR` → `$LOCAL_DIR`)
- stale file references in README (`utils.sh`, `variables.sh`, `backups/zsh/`)
### Changed
- README install steps reflect zinit (no longer mention Oh My Zsh)
### Removed
- Oh My Zsh scaffolding: `ZSH`/`ZSH_CUSTOM`/`OMZSH_DIR` exports, `ZSH_THEME`/`CASE_SENSITIVE` vars, `zsh_plugins()` function, OMZ + p10k install blocks in `installation.sh` (zinit handles plugins and theme)



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


