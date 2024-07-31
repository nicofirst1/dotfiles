
# check if $HOME/.pyenv exists
if [ -d $HOME/.pyenv ]; then
    eval "$(pyenv init -)"
    export PATH="$HOME/.pyenv/bin:$PATH"
fi

