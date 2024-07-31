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



# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
source_if_exists "$CONFIG_DIR/zsh/.p10k.zsh"



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


source_if_exists $ZSH/oh-my-zsh.sh

# python stuff
source_if_exists $CONFIG_DIR/python/settings.sh


# User configuration

# Agnoster & Powerlevel10k stuff
DEFAULT_USER=`whoami`

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
source_if_exists $CONFIG_DIR/zsh/.p10k.zsh


# Aliases
source_if_exists $ALIASES_F

# Fix background for zsh-autocompletion
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=4'



# FZF setup
source_if_exists $CONFIG_DIR/fzf/fzf-init
source_if_exists $CONFIG_DIR/fzf/fzf-fn


# the fuck 
eval "$(thefuck --alias)"
eval "$(zoxide init zsh)"

source_if_exists $ENTR_CONFIG

# source machine dependent stuff, for example conda
source_if_exists $MACHINE_SOURCE

[ -f "${XDG_CONFIG_HOME:-$HOME/.config}"/fzf/fzf.zsh ] && source "${XDG_CONFIG_HOME:-$HOME/.config}"/fzf/fzf.zsh
