######################################
# ENVIRONMENT VARIABLES
######################################

source $HOME/dotfiles/scripts/exports.sh


# macOS specific configurations
if [[ "$OSTYPE" == "darwin"* ]]; then
    
    source $DARWIN_SETTING_F

elif [[ "$OSTYPE" == "linux-gnu"* ]]; then

    source $LINUX_SETTING_F


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


source $ZSH/oh-my-zsh.sh

# User configuration

# Agnoster & Powerlevel10k stuff
DEFAULT_USER=`whoami`

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ -f $CONFIG_DIR/zsh/.p10k.zsh ]] && source $CONFIG_DIR/zsh/.p10k.zsh



# Aliases
source $ALIASES_F

# Fix background for zsh-autocompletion
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=6'


# FZF setup
[ -f $CONFIG_DIR/zsh/.fzf.zsh ] && source $CONFIG_DIR/zsh/.fzf.zsh
source $CONFIG_DIR/fzf/git.sh

# the fuck 
#eval $(thefuck --alias)
eval "$(zoxide init zsh)"

# source machine dependent stuff, for example conda
source $MACHINE_SOURCE
