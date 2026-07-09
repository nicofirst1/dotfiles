# .zshenv — the ONE zsh file that must live in $HOME. zsh reads $HOME/.zshenv
# before ZDOTDIR exists, so it can't be relocated to XDG without editing the
# system /etc/zshenv. Keep it minimal: point ZDOTDIR at $XDG_CONFIG_HOME/zsh and
# hand off. The real env config lives in $ZDOTDIR/.zshenv, interactive config in
# $ZDOTDIR/.zshrc, and login/PATH bootstrap (brew…) in $ZDOTDIR/.zprofile — all
# read automatically by zsh once ZDOTDIR is set.
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"

[[ -r "$ZDOTDIR/.zshenv" ]] && source "$ZDOTDIR/.zshenv"
