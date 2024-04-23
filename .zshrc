######################################
# ENVIRONMENT VARIABLES
######################################

source variables
# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"



# If you come from bash you might have to change your $PATH.
# Adjust PATH for different OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux-specific PATH adjustments
    # Example for a common path in Linux environments
    export PATH="$PATH:$HOME/.local/bin"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS-specific PATH adjustments
    export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
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
  zsh-z
)

# macOS specific configurations
if [[ "$OSTYPE" == "darwin"* ]]; then
    plugins=($plugins brew macos)
    # Homebrew Ruby setup
    source $(brew --prefix)/opt/chruby/share/chruby/chruby.sh
    source $(brew --prefix)/opt/chruby/share/chruby/auto.sh
    # Autojump
    [[ -s `brew --prefix`/etc/autojump.sh ]] && . `brew --prefix`/etc/autojump.sh

    # Ruby version management
    chruby ruby-3.3.0
    
   # source colorls
    source $(dirname $(gem which colorls))/tab_complete.sh

elif [[ "$OSTYPE" == "linux-gnu"* ]]; then

    source $REPO_DIR/chruby/share/chruby/chruby.sh
    source $REPO_DIR/chruby/share/chruby/auto.sh

fi


source $ZSH/oh-my-zsh.sh

# User configuration

# Agnoster & Powerlevel10k stuff
DEFAULT_USER=`whoami`

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh



# Aliases
alias src="source activate"
# Check if Ruby is installed
if command -v ruby &> /dev/null; then
    alias ls="colorls"
    alias la='colorls -lA --sd'
else
    alias la='ls -lA'
fi

# SSH shortcuts
alias juwels-booster="ssh brandizzi1@juwels-booster.fz-juelich.de"
alias juwels-cluster="ssh brandizzi1@juwels-cluster.fz-juelich.de"
alias bernard="ssh nibr274g@login2.barnard.hpc.tu-dresden.de"
alias dgx2="ssh dgx2"



# Fix background for zsh-autocompletion
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=6'

# Source custom commands
export PATH="$HOME/.poetry/bin:$PATH"
export PATH="/usr/local/opt/ruby/bin:/usr/local/lib/ruby/gems/3.0.0/bin:$PATH"
export PATH="$HOME/.gem/ruby/3.0.0/bin:$PATH"

# FZF setup
[ -f $HOME/.fzf.zsh ] && source $HOME/.fzf.zsh
source $REPOS/fzf-git/fzf-git.sh

# the fuck 
eval $(thefuck --alias)

# source machine dependent stuff, for example conda
source $MACHINE_SOURCE
