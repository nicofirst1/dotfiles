export PATH="$PATH:$HOME/.local/bin"
export PATH="$CARGO_HOME/bin:$PATH"

# Word-wise navigation and deletion to match the iTerm2 / macOS muscle memory.
# Ptyxis (and other VTE terminals) emit different escape sequences than iTerm
# does for Ctrl/Alt + arrows / backspace / delete, so the default zsh
# bindings for ^[b / ^[f aren't enough on Linux.
bindkey '^[[1;5D' backward-word     # Ctrl+Left
bindkey '^[[1;5C' forward-word      # Ctrl+Right
bindkey '^[[1;3D' backward-word     # Alt+Left
bindkey '^[[1;3C' forward-word      # Alt+Right
bindkey '^H'      backward-kill-word # Ctrl+Backspace
bindkey '^[^?'    backward-kill-word # Alt+Backspace
bindkey '^[[3;5~' kill-word          # Ctrl+Delete
bindkey '^[[3;3~' kill-word          # Alt+Delete
bindkey '^[[H'    beginning-of-line  # Home
bindkey '^[[F'    end-of-line        # End
