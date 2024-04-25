# This script defines various aliases for convenient command line usage.

# Alias to activate a virtual environment
alias src="source activate"

# Check if lsd is installed and set aliases accordingly
if command -v lsd &> /dev/null; then
    alias ls="lsd"
    alias la='lsd -A'
    alias lsa='lsd -lA'
else
    alias la='ls -lA'
fi

# Check if bat is installed and set aliases accordingly
if command -v bat &> /dev/null; then
    alias cat="bat"
    alias fzf="fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'"

    # Function to tail -f a file with bat
    tf() {
        tail -f $1 | bat --paging=never -l log
    }
    
    # Function to show git diff with bat
    batdiff() {
        git diff --name-only --relative --diff-filter=d | xargs bat --diff
    }
fi