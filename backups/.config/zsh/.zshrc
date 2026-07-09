######################################
# INTERACTIVE SHELL CONFIG
######################################
#zmodload zsh/zprof

# Environment variables (DOTFILES_DIR, XDG dirs, tool redirects) are set in
# .zshenv so they reach non-interactive shells too. This file is interactive-
# only: prompt, plugins, aliases, completions.
source $UTILS_F



# macOS specific configurations
if [[ "$OSTYPE" == "darwin"* ]]; then
    
    source $DARWIN_SETTING_F

elif [[ "$OSTYPE" == "linux-gnu"* ]]; then

    source $LINUX_SETTING_F


fi

# Load zinit
source "$ZINIT_HOME/zinit.zsh"


# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
source "$CONFIG_DIR/zsh/.p10k.zsh"


# Load Powerlevel10k theme with Turbo Mode
zinit ice depth"1" # git clone depth
zinit light romkatv/powerlevel10k

# compinit optimization and caching
autoload -Uz compinit
if [ -z "$ZSH_COMPDUMP" ]; then
  ZSH_COMPDUMP="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-${SHORT_HOST}-${ZSH_VERSION}"
fi
[[ -d ${ZSH_COMPDUMP:h} ]] || mkdir -p ${ZSH_COMPDUMP:h}
# Run the full compaudit security check at most once a day. On warm cache
# (file exists AND was rebuilt within the last 24h) skip the audit with -C —
# saves ~25ms per shell start. Wrapped in an anonymous function so
# extended_glob (required for the `(#qN.mh-24)` qualifier) stays local.
() {
  setopt local_options extended_glob
  if [[ -f $ZSH_COMPDUMP && -n $ZSH_COMPDUMP(#qN.mh-24) ]]; then
    compinit -C -d $ZSH_COMPDUMP
  else
    compinit -d $ZSH_COMPDUMP
  fi
}
if [[ -f $ZSH_COMPDUMP.zwc && $ZSH_COMPDUMP -nt $ZSH_COMPDUMP.zwc ]]; then
  zcompile $ZSH_COMPDUMP
fi

# Make autosuggestion remember history
# from here https://github.com/zsh-users/zsh-autosuggestions/issues/645#issuecomment-1452340220
setopt APPEND_HISTORY
setopt SHARE_HISTORY
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
[[ -d ${HISTFILE:h} ]] || mkdir -p ${HISTFILE:h}
SAVEHIST=1000
HISTSIZE=999
setopt HIST_EXPIRE_DUPS_FIRST
setopt EXTENDED_HISTORY

# Load plugins with zinit using Turbo Mode and lazy loading.
# wait'0' defers until after the first prompt renders — instant-prompt hides
# the gap, so the shell feels interactive immediately.
zinit ice wait'0' lucid
zinit light zsh-users/zsh-autosuggestions

zinit ice wait'1' lucid
zinit light zsh-users/zsh-syntax-highlighting

zinit ice wait'1' lucid
zinit light agkozak/zsh-z

zinit ice wait'3' lucid
zinit light zdharma-continuum/history-search-multi-word

# zinit ice wait'3' lucid
# zinit light wfxr/forgit

zinit ice wait'1' lucid
zinit light zsh-users/zsh-completions


zinit ice wait'2' lucid
zinit light zdharma-continuum/fast-syntax-highlighting


# Load a few important annexes, without Turbo
# (this is currently required for annexes)
zinit light-mode for \
    zdharma-continuum/zinit-annex-as-monitor \
    zdharma-continuum/zinit-annex-bin-gem-node \
    zdharma-continuum/zinit-annex-patch-dl \
    zdharma-continuum/zinit-annex-rust

### End of Zinit's installer chunk


# User configuration

# Agnoster & Powerlevel10k stuff
DEFAULT_USER=$(whoami)

OPENCODE_CONFIG_DIR="$CONFIG_DIR/opencode"

# Aliases
source $ALIASES_F

# Fix background for zsh-autocompletion
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=4'


# FZF setup
source "$CONFIG_DIR/fzf/fzf-init"

# if python is installed
if command -v python3 &> /dev/null; then
   source $CONFIG_DIR/python/settings.sh
fi


# thefuck — gated on both presence AND a working invocation, since Python 3.14
# dropped `distutils` and breaks unmaintained thefuck installs at import time.
# `thefuck --alias` boots a full Python interpreter (~280ms) on every shell
# start just to print a static function body — cache it like pyenv above.
if command -v thefuck &> /dev/null; then
    _thefuck_cache="${XDG_CACHE_HOME:-$HOME/.cache}/thefuck-alias.zsh"
    () {
        setopt local_options extended_glob
        if [[ ! -s $_thefuck_cache || -z $_thefuck_cache(#qN.mh-24) ]]; then
            thefuck --alias > $_thefuck_cache 2>/dev/null || rm -f $_thefuck_cache
        fi
    }
    [[ -s $_thefuck_cache ]] && source $_thefuck_cache
    unset _thefuck_cache
fi

#source $ENTR_CONFIG

# source machine dependent stuff, for example conda
[ -f "$MACHINE_SOURCE" ] && source "$MACHINE_SOURCE"

[ -f "${XDG_CONFIG_HOME:-$HOME/.config}"/fzf/fzf.zsh ] && source "${XDG_CONFIG_HOME:-$HOME/.config}"/fzf/fzf.zsh

# Run zinit cdreplay to set up completions after plugins are loaded
zinit cdreplay -q



#zprof

# opencode
[ -d "$HOME/.opencode/bin" ] && export PATH="$HOME/.opencode/bin:$PATH"

# Google Cloud SDK (only present on the mac install — path resolves at runtime)
if [ -f "$HOME/Downloads/google-cloud-sdk/path.zsh.inc" ]; then . "$HOME/Downloads/google-cloud-sdk/path.zsh.inc"; fi
if [ -f "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc" ]; then . "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc"; fi
