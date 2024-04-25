######################################
# ENVIRONMENT VARIABLES
######################################

source $HOME/dotfiles/scripts/variables.sh
# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# macOS specific configurations
if [[ "$OSTYPE" == "darwin"* ]]; then
    
    source $CONFIG_DIR/zsh/darwin_settings.zsh

elif [[ "$OSTYPE" == "linux-gnu"* ]]; then

    source $CONFIG_DIR/zsh/linux_settings.zsh


fi



# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi



# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded.
ZSH_THEME="powerlevel10k/powerlevel10k"

# Uncomment the following line to use case-sensitive completion.
CASE_SENSITIVE="true"

# Plugins
plugins=(
  git
  colorize
  pip
  python
  extract
  zsh-autosuggestions
  history-search-multi-word
  forgit
  zsh-syntax-highlighting
)

eval "$(zoxide init zsh)"


source $ZSH/oh-my-zsh.sh

# User configuration

# Agnoster & Powerlevel10k stuff
DEFAULT_USER=`whoami`

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ -f $CONFIG_DIR/zsh/.p10k.zsh ]] && source $CONFIG_DIR/zsh/.p10k.zsh



# Aliases
source $CONFIG_DIR/aliases.sh

# Fix background for zsh-autocompletion
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=6'


# FZF setup
[ -f $CONFIG_DIR/zsh/.fzf.zsh ] && source $CONFIG_DIR/zsh/.fzf.zsh
source $CONFIG_DIR/fzf/git.sh

# the fuck 
#eval $(thefuck --alias)

# source machine dependent stuff, for example conda
source $MACHINE_SOURCE
