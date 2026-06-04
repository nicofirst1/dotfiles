#!/usr/bin/env bash
#
# install-agentmemory.sh  —  standalone agentmemory provisioner
#
# NOT called by installation.sh on purpose: agentmemory is a heavy, optional
# runtime (a local 7B model + a global npm daemon). Run this by hand on a
# machine where you actually want the memory engine:
#
#     bash ~/dotfiles/scripts/install-agentmemory.sh
#
# It reproduces the setup we run today:
#   1. Ollama (the local LLM server)               -> brew cask, started
#   2. the mistral:7b-instruct model               -> ollama pull
#   3. @agentmemory/agentmemory@0.9.25 (the daemon)-> npm -g
#   4. ~/.agentmemory/.env                          -> our fully-local config
#                                                      (written only if absent;
#                                                       never clobbers real keys)
#   5. the LaunchAgents (daemon + battery power-guard) -> stowed + loaded
#
# Idempotent: every step is skipped if already satisfied. Safe to re-run.
# macOS only (brew cask + launchctl + the battery guard are Darwin-specific).

set -euo pipefail

AM_VERSION="0.9.25"               # pin to the version this config was written for
AM_MODEL="mistral:7b-instruct"    # the local LLM agentmemory talks to
OLLAMA_URL="http://localhost:11434"

# Resolve the dotfiles dir from this script's own location, so it works wherever
# the repo is cloned.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SELF/.." && pwd)"
EXPORT_ROOT="${HOME}/repos/personal/claude_memory"   # Obsidian auto-export target

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Exact-match helpers via awk. awk consumes ALL of its stdin, so the upstream
# producer never gets SIGPIPE — which `grep -q` would cause (it exits on first
# match, and under `set -o pipefail` the producer's SIGPIPE fails the pipeline
# even on a match). awk also lets us match the label/model column exactly,
# avoiding substring false-positives (e.g. the daemon label is a prefix of the
# power-guard label).
agent_loaded()  { launchctl list 2>/dev/null | awk -v l="$1" '$3==l{f=1} END{exit f?0:1}'; }
model_present() { ollama list  2>/dev/null | awk -v m="$1" 'NR>1 && $1==m{f=1} END{exit f?0:1}'; }

# --- preconditions ----------------------------------------------------------
[[ "$OSTYPE" == darwin* ]] || die "macOS only (uses brew casks + launchctl)."
command -v brew >/dev/null || die "Homebrew missing — run scripts/installation.sh first."
command -v node >/dev/null || die "node missing — run scripts/installation.sh first."
command -v npm  >/dev/null || die "npm missing — run scripts/installation.sh first."

# --- 1. Ollama --------------------------------------------------------------
if command -v ollama >/dev/null; then
    say "Ollama already installed ($(ollama --version 2>/dev/null | head -1))."
else
    say "Installing Ollama (cask)..."
    brew install --cask ollama
fi

# Make sure the Ollama server is up (the .app runs a background server on :11434).
if ! curl -fsS "$OLLAMA_URL/api/version" >/dev/null 2>&1; then
    say "Starting the Ollama server..."
    open -ga Ollama 2>/dev/null || (ollama serve >/dev/null 2>&1 &)
    for _ in $(seq 1 30); do
        curl -fsS "$OLLAMA_URL/api/version" >/dev/null 2>&1 && break
        sleep 1
    done
    curl -fsS "$OLLAMA_URL/api/version" >/dev/null 2>&1 \
        || warn "Ollama API not reachable at $OLLAMA_URL yet — start the app manually."
fi

# --- 2. the model -----------------------------------------------------------
if model_present "$AM_MODEL"; then
    say "Model $AM_MODEL already pulled."
else
    say "Pulling $AM_MODEL (~4 GB)..."
    ollama pull "$AM_MODEL"
fi

# --- 3. the agentmemory daemon ---------------------------------------------
# `|| true`: npm ls exits non-zero when the package is absent, which would trip
# errexit; we only care about parsing the version (empty if not installed).
INSTALLED_AM="$(npm ls -g --depth=0 @agentmemory/agentmemory 2>/dev/null \
                | sed -nE 's/.*@agentmemory\/agentmemory@([0-9.]+).*/\1/p' || true)"
INSTALLED_AM="${INSTALLED_AM%%$'\n'*}"   # first line only, without a pipe-to-head
if [[ "$INSTALLED_AM" == "$AM_VERSION" ]]; then
    say "agentmemory@$AM_VERSION already installed globally."
else
    say "Installing @agentmemory/agentmemory@$AM_VERSION globally..."
    npm install -g "@agentmemory/agentmemory@$AM_VERSION"
fi

# --- 4. ~/.agentmemory/.env (our fully-local config) ------------------------
mkdir -p "${HOME}/.agentmemory"
mkdir -p "$EXPORT_ROOT"
ENV_FILE="${HOME}/.agentmemory/.env"
if [[ -f "$ENV_FILE" ]]; then
    say ".env already present — left untouched (preserves any real API keys)."
else
    say "Writing $ENV_FILE (fully-local config)..."
    # Quoted heredoc => written literally; EXPORT_ROOT substituted afterwards.
    cat > "$ENV_FILE" <<'ENV'
# =============================================================================
# agentmemory — fully-local config (written by install-agentmemory.sh)
# =============================================================================
# LLM + embeddings both run on-device. No cloud spend, no real keys required.
# Edit freely; the battery power-guard appends/removes a managed block at EOF.

# --- LLM: local Ollama via the OpenAI-compatible path ------------------------
# OPENAI_API_KEY only needs to be NON-EMPTY for agentmemory to enable the
# OpenAI provider; Ollama ignores the value. Leave it as the sentinel below.
OPENAI_API_KEY=ollama
OPENAI_MODEL=mistral:7b-instruct
OPENAI_BASE_URL=http://localhost:11434

# --- Embeddings: on-device @xenova BGE-small (384d), zero cost/quota ---------
EMBEDDING_PROVIDER=local

# --- Optional cloud fallback (dormant) --------------------------------------
# Fill in and uncomment only if you want a cloud LLM/embedding fallback.
# GEMINI_API_KEY=
# GEMINI_MODEL=gemini-2.5-flash

# --- Behaviour flags (these are what the battery power-guard toggles) --------
AGENTMEMORY_AUTO_COMPRESS=true     # LLM-compress every observation batch (local => free)
AGENTMEMORY_INJECT_CONTEXT=true    # inject recalled memories back into prompts
CONSOLIDATION_ENABLED=true         # 4-tier consolidation pipeline
CONSOLIDATION_DECAY_DAYS=10        # age after which non-reinforced memories decay
GRAPH_EXTRACTION_ENABLED=true      # extract concept-graph edges on remember
GRAPH_EXTRACTION_BATCH_SIZE=8
AGENTMEMORY_REFLECT=true           # periodically auto-synthesize lessons
AGENTMEMORY_DROP_STALE_INDEX=false # guard against silent index drops on dim change

# --- Obsidian export --------------------------------------------------------
AGENTMEMORY_EXPORT_ROOT=__EXPORT_ROOT__
OBSIDIAN_AUTO_EXPORT=true
ENV
    # Substitute the export root (kept out of the literal heredoc for portability).
    /usr/bin/sed -i '' "s#__EXPORT_ROOT__#${EXPORT_ROOT}#" "$ENV_FILE"
fi

# --- 5. LaunchAgents: stow the symlinks, then load --------------------------
if command -v stow >/dev/null; then
    say "Stowing the launchagents package..."
    stow --dir="$DOTFILES_DIR" --target="$HOME" --restow launchagents
else
    warn "stow not found — skipping symlink step (run scripts/installation.sh)."
fi

for plist in "$DOTFILES_DIR"/launchagents/Library/LaunchAgents/*.plist; do
    [[ -e "$plist" ]] || continue
    label="$(basename "$plist" .plist)"
    target="${HOME}/Library/LaunchAgents/$(basename "$plist")"
    if agent_loaded "$label"; then
        say "$label already loaded."
    elif [[ -e "$target" ]]; then
        say "Loading $label..."
        launchctl bootstrap "gui/$(id -u)" "$target" 2>/dev/null \
            || warn "could not bootstrap $label (load manually after next login)."
    fi
done

# --- done -------------------------------------------------------------------
say "agentmemory provisioned. Quick check:"
curl -fsS "$OLLAMA_URL/api/version" >/dev/null 2>&1 && echo "  • Ollama API: up" || echo "  • Ollama API: DOWN"
model_present "$AM_MODEL"                       && echo "  • Model $AM_MODEL: present" || echo "  • Model: MISSING"
agent_loaded com.nbrandizzi.agentmemory        && echo "  • Daemon: loaded"        || echo "  • Daemon: not loaded"
agent_loaded com.nbrandizzi.agentmemory-power-guard && echo "  • Battery guard: loaded" || echo "  • Battery guard: not loaded"
echo
echo "Note: the daemon binds :3111 (engine) and :3113 (viewer). Give it a few"
echo "seconds, then: agentmemory status"
