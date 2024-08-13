######################################
# ENVIRONMENT VARIABLES
######################################

source $HOME/dotfiles/scripts/exports.sh
source $UTILS_F



# macOS specific configurations
if [[ "$OSTYPE" == "darwin"* ]]; then
    
    source $DARWIN_SETTING_F

elif [[ "$OSTYPE" == "linux-gnu"* ]]; then

    source $LINUX_SETTING_F


fi

# Load zinit
source $ZINIT_HOME/zinit.zsh


# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
source "$CONFIG_DIR/zsh/.p10k.zsh"



# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded.
ZSH_THEME="powerlevel10k/powerlevel10k"

# Uncomment the following line to use case-sensitive completion.
CASE_SENSITIVE="true"

# compinit optimization and caching
autoload -Uz compinit
if [ -z "$ZSH_COMPDUMP" ]; then
  ZSH_COMPDUMP="${ZDOTDIR:-$HOME}/.zcompdump-${SHORT_HOST}-${ZSH_VERSION}"
fi
if [[ -f $ZSH_COMPDUMP.zwc && $ZSH_COMPDUMP -nt $ZSH_COMPDUMP.zwc ]]; then
  zcompile $ZSH_COMPDUMP
fi
compinit -d $ZSH_COMPDUMP

# Load plugins with zinit
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-syntax-highlighting
zinit light zdharma-continuum/history-search-multi-word
zinit light wfxr/forgit
zinit light zsh-users/zsh-completions
zinit light rupa/z
zinit light zdharma-continuum/fast-syntax-highlighting
zinit light zdharma-continuum/zinit


# Load Powerlevel10k theme
zinit ice depth=1; zinit light romkatv/powerlevel10k


# User configuration

# Agnoster & Powerlevel10k stuff
DEFAULT_USER=`whoami`


# Aliases
source $ALIASES_F

# Fix background for zsh-autocompletion
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=4'



# FZF setup
source $CONFIG_DIR/fzf/fzf-init
source $CONFIG_DIR/fzf/fzf-fn


# the fuck 
eval "$(thefuck --alias)"
eval "$(zoxide init zsh)"

source $ENTR_CONFIG

# source machine dependent stuff, for example conda
source $MACHINE_SOURCE

[ -f "${XDG_CONFIG_HOME:-$HOME/.config}"/fzf/fzf.zsh ] && source "${XDG_CONFIG_HOME:-$HOME/.config}"/fzf/fzf.zsh

# Load a few important annexes, without Turbo
# (this is currently required for annexes)
zinit light-mode for \
    zdharma-continuum/zinit-annex-as-monitor \
    zdharma-continuum/zinit-annex-bin-gem-node \
    zdharma-continuum/zinit-annex-patch-dl \
    zdharma-continuum/zinit-annex-rust

### End of Zinit's installer chunk
