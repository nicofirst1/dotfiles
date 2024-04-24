alias src="source activate"



# check if lsd is installed
if command -v lsd &> /dev/null; then
    alias ls="lsd"
    alias la='lsd -lA'
    alias lsa='lsd -lA'
else
    alias la='ls -lA'
fi


# check if bat is installed
if command -v bat &> /dev/null; then
    alias cat="bat"
    alias fzf="fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'"

fi