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

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

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
)

# macOS specific configurations
if [[ "$OSTYPE" == "darwin"* ]]; then
    plugins=($plugins brew macos)
    # Homebrew Ruby setup
    source $(brew --prefix)/opt/chruby/share/chruby/chruby.sh
    source $(brew --prefix)/opt/chruby/share/chruby/auto.sh
    # Autojump
    [[ -s `brew --prefix`/etc/autojump.sh ]] && . `brew --prefix`/etc/autojump.sh
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

# Ruby version management
chruby 3.3.0

# Aliases
alias src="source activate"
alias ls="colorls"
alias la='colorls -lA --sd'

# SSH shortcuts
alias juwels-booster="ssh brandizzi1@juwels-booster.fz-juelich.de"
alias juwels-cluster="ssh brandizzi1@juwels-cluster.fz-juelich.de"
alias bernard="ssh nibr274g@login2.barnard.hpc.tu-dresden.de"
alias dgx2="ssh dgx2"

# source colorls
source $(dirname $(gem which colorls))/tab_complete.sh

# chruby
source $HOMEBREW_PREFIX/opt/chruby/share/chruby/chruby.sh

# Fix background for zsh-autocompletion
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=6'

# Source custom commands
export PATH="$HOME/.poetry/bin:$PATH"
export PATH="/usr/local/opt/ruby/bin:/usr/local/lib/ruby/gems/3.0.0/bin:$PATH"
export PATH="$HOME/.gem/ruby/3.0.0/bin:$PATH"

# FZF setup
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
source ~/Repos/fzf-git/fzf-git.sh

# the fuck 
eval $(thefuck --alias)

# Conda initialize
# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/Users/nbrandizzi/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/Users/nbrandizzi/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/Users/nbrandizzi/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/Users/nbrandizzi/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<
