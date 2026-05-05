# This script contains utility functions for installing various tools and dependencies.
# It includes functions for installing chruby, Mackup, Python, Zsh plugins, Zsh, GNU Stow, Rust, and Rust plugins.
# Each function checks the operating system and installs the necessary dependencies accordingly.
# The script also includes a function for restoring backups using GNU Stow.

# Note: This script assumes the presence of certain environment variables, such as $OSTYPE, $REPO_DIR, and $DOTFILES_DIR.
# Make sure to set these variables appropriately before running the script.
_functions_self="$(readlink -f "${BASH_SOURCE[0]:-${(%):-%x}}")"
source "$(dirname "$_functions_self")/exports.sh"
unset _functions_self

#########################
#        ZSH            #
#########################

# install_zsh():
# This function clones the Zsh repository from SourceForge and installs Zsh.
# It configures and compiles Zsh with a custom prefix.
install_zsh() {

    # clone the zsh repo
    git clone git://git.code.sf.net/p/zsh/code $REPO_DIR/zsh
    cd $REPO_DIR/zsh

    # configure and install 
    (
    cd $REPO_DIR/zsh
    # https://unix.stackexchange.com/questions/673669/installing-zsh-from-source-file-without-root-user-access
    ./Util/preconfig
    CPPFLAGS="-I$LOCAL_DIR/include" LDFLAGS="-L$LOCAL_DIR/lib" ./configure --prefix=$LOCAL_DIR
    make
    make install
    )

}

# install_gnustow():
# This function installs GNU Stow, a symlink farm manager.
# It downloads the latest version of GNU Stow, extracts it, and installs it with a custom prefix.
install_gnustow() {

    # check if stow is already installed
    if command -v stow &>/dev/null; then
        echo "GNU Stow is already installed."
        return
    fi

    curl -o $REPO_DIR/stow-latest.tar.gz  https://ftp.gnu.org/gnu/stow/stow-latest.tar.gz 

    tar -xzvf $REPO_DIR/stow-latest.tar.gz -C $REPO_DIR
    # Extract the tarball in the $REPO_DIR directory
    rm $REPO_DIR/stow-latest.tar.gz

    mv $REPO_DIR/stow-*/ $REPO_DIR/stow

    STOW_DIR=$REPO_DIR/stow

    # configure and install 
    (
    cd $STOW_DIR
    ./configure --prefix=$LOCAL_DIR
    make
    make install
    )

}

# stow_restore():
# This function restores backups created with GNU Stow.
# It uses GNU Stow to restow the backups to the target directory.
stow_restore() {
    stow --dir=$DOTFILES_DIR --target=$HOME --restow backups
}

#########################
#        Python         #
#########################

# install_mackup():
# This function installs Mackup, a utility for backing up and restoring application settings.
# It checks if Python is available and installs Mackup using pip or pip3.
install_mackup() {

    # Check for Python and install Mackup
    if command -v python &>/dev/null || command -v python3 &>/dev/null; then
        echo "Installing Mackup..."
        pip install --user --upgrade mackup || pip3 install --user --upgrade mackup
    else
        echo "Python is not available."

    fi

}

# check_python():
# This function checks if Python is installed.
# If Python is not installed, it checks if module load is available on Linux.
# If module load is available, it attempts to load the Python module.
# If module load is not available or Python is not installed, it displays an error message.

check_python() {
    if ! command -v python &>/dev/null && ! command -v python3 &>/dev/null; then
        echo "Python is not installed."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            echo "Checking if module load is available..."
            if command -v module &>/dev/null; then
                echo "Module load is available. Attempting to load Python module..."
                module load python || { echo "Failed to load Python module. Please ensure Python is installed."; }
            else
                echo "Module load is not available. Please install Python manually."
            fi
        else
            echo "Unknown operating system. Please install Python manually."
        fi
    else
        echo "Python is already installed."
    fi
}

#########################
#         Rust          #
#########################

# install_rust():
# This function checks if Rust is installed.
# If Rust is not found, it installs Rust using the official Rustup installer.
install_rust() {
    # Check if Rust is installed
    if ! command -v rustc &>/dev/null; then
        echo "Rust not found. Installing..."
        # `-s -- -y` forwards flags to rustup-init so it skips the interactive
        # prompt — required when running from non-interactive bootstraps.
        # `--default-toolchain stable` is set explicitly because some rustup
        # builds otherwise leave the default unset, requiring a manual
        # `rustup default stable` before any toolchain command works.
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
            sh -s -- -y --no-modify-path --default-toolchain stable
    fi

    # Make rustc/cargo available in this shell session for the plugin install
    # that runs immediately after, even on a fresh install.
    [ -f "$CARGO_HOME/env" ] && source "$CARGO_HOME/env"
}

# install_rust_plugins():
# Installs CLI rewrites in Rust via cargo — but skips any tool that's already
# on PATH (e.g. apt-installed lsd/bat/zoxide on Linux), since cargo from-source
# builds add ~5 min each.
install_rust_plugins() {

    # Check if Rust is installed
    install_rust

    cargo_install_if_missing() {
        local bin="$1" crate="$2"
        shift 2
        if command -v "$bin" &>/dev/null; then
            echo "$bin already installed, skipping cargo build"
        else
            cargo install "$@" "$crate"
        fi
    }

    cargo_install_if_missing lsd     lsd     --locked
    cargo_install_if_missing bat     bat     --locked
    cargo_install_if_missing zoxide  zoxide  --locked
    cargo_install_if_missing tldr    tlrc    --locked
}


#########################
#        TMUX           #
#########################

install_libevent(){

    #check if '$REPO_DIR/libevent' already exists and assume installation
    if [ -d "$REPO_DIR/libevent" ]; then
        echo "libevent is already installed."
        return
    fi

    latest_url="https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.tar.gz"
    
    echo "Downloading libevent from $latest_url"

    curl -Ls -o $REPO_DIR/libevent.tar.gz  $latest_url
    
    tar -xzvf $REPO_DIR/libevent.tar.gz -C $REPO_DIR/
    rm $REPO_DIR/libevent.tar.gz

    mv $REPO_DIR/libevent-*/ $REPO_DIR/libevent

    LIBEVENT_DIR=$REPO_DIR/libevent

    # configure and install 
    (
        cd $LIBEVENT_DIR
        ./configure --prefix=$LOCAL_DIR  --enable-shared 
        make
        make install
    )
}

install_ncurses(){

    # check for the file 'ncurses6-config' in $LOCAL_DIR/bin
    if [ -f "$LOCAL_DIR/bin/ncurses6-config" ]; then
        echo "ncurses is already installed."
        return
    fi

    latest_url="https://invisible-island.net/datafiles/release/ncurses.tar.gz"

    echo "Downloading ncurses from $latest_url"

    curl -Ls -o $REPO_DIR/ncurses.tar.gz  $latest_url
    
    tar -xzvf $REPO_DIR/ncurses.tar.gz -C $REPO_DIR/
    rm $REPO_DIR/ncurses.tar.gz

    mv $REPO_DIR/ncurses-*/ $REPO_DIR/ncurses

    ncurses_dir=$REPO_DIR/ncurses

    mkdir -p $LOCAL_DIR/lib/pkgconfig

    # configure and install
    (
        cd $ncurses_dir
        ./configure --prefix=$LOCAL_DIR --with-shared --with-termlib --enable-pc-files --with-pkg-config-libdir=$LOCAL_DIR/lib/pkgconfig
        make
        make install
    )
}

install_tmux(){

    # Build tmux from source only when the package manager didn't already
    # provide it (apt covers the Linux path; brew covers macOS).
    if ! command -v tmux &>/dev/null; then
        install_libevent
        install_ncurses

        git clone --depth 1 https://github.com/tmux/tmux.git $REPO_DIR/tmux

        (
            cd $REPO_DIR/tmux
            git fetch --unshallow
            ./autogen.sh
            PKG_CONFIG_PATH="$LOCAL_DIR/lib/pkgconfig" ./configure  --prefix=$LOCAL_DIR
            make
            make install
        )
    else
        echo "tmux is already installed ($(tmux -V))."
    fi

    # oh-my-tmux config — clone if missing, then symlink the main .tmux.conf
    # to ~/.tmux.conf. We deliberately use the legacy path (not XDG) because
    # ~/.config/tmux/ is itself a stow symlink into this repo: anything
    # dropped there pollutes the working tree. With ~/.tmux.conf, oh-my-tmux
    # also picks ~/.tmux/plugins/ as TMUX_PLUGIN_MANAGER_PATH automatically
    # (see oh-my-tmux .tmux.conf line ~1815), keeping cloned plugins out of
    # the stow target. tmux.conf.local stays stowed at
    # ~/.config/tmux/tmux.conf.local — oh-my-tmux source-files it via XDG.
    if [ ! -d "$REPO_DIR/oh-my-tmux" ]; then
        git clone https://github.com/gpakosz/.tmux.git "$REPO_DIR/oh-my-tmux"
    fi
    ln -sfn "$REPO_DIR/oh-my-tmux/.tmux.conf" "$HOME/.tmux.conf"
}


#########################
#     NERD FONTS        #
#########################

# install_nerd_font():
# Powerlevel10k's prompt uses Nerd Font glyphs (the four MesloLGS NF files).
# On macOS users typically install via brew cask; on Linux there's no
# distro-standard package, so drop them into the user's fontconfig dir and
# refresh the cache. After this the user still has to point their terminal
# emulator at "MesloLGS NF" — that part can't be automated portably.
install_nerd_font() {
    local font_dir
    if [[ "$OSTYPE" == "darwin"* ]]; then
        font_dir="$HOME/Library/Fonts"
    else
        font_dir="$HOME/.local/share/fonts"
    fi
    mkdir -p "$font_dir"

    # Skip if already installed (fontconfig on linux, or file presence on mac).
    if [[ "$OSTYPE" != "darwin"* ]] && fc-list 2>/dev/null | grep -q 'MesloLGS NF'; then
        echo "MesloLGS NF already installed, skipping"
        return
    fi
    if [[ "$OSTYPE" == "darwin"* ]] && [[ -f "$font_dir/MesloLGS NF Regular.ttf" ]]; then
        echo "MesloLGS NF already installed, skipping"
        return
    fi

    local base="https://github.com/romkatv/powerlevel10k-media/raw/master"
    for variant in "Regular" "Bold" "Italic" "Bold%20Italic"; do
        local pretty="${variant//%20/ }"
        curl -fsSL -o "$font_dir/MesloLGS NF ${pretty}.ttf" \
            "$base/MesloLGS%20NF%20${variant}.ttf"
    done

    # Linux only — fontconfig needs a refresh; macOS picks up new fonts on its own.
    if [[ "$OSTYPE" != "darwin"* ]] && command -v fc-cache &>/dev/null; then
        fc-cache -f "$font_dir"
    fi

    echo "MesloLGS NF installed to $font_dir."
    echo "Set your terminal emulator's font to 'MesloLGS NF' to see Powerlevel10k icons."
}

#########################
#        FZF            #
#########################

install_fzf(){

    # check if installed
    if command -v fzf &>/dev/null; then
        echo "fzf is already installed."
        return
    fi

    git clone https://github.com/junegunn/fzf.git  $REPO_DIR/fzf
    
        (
            cd $REPO_DIR/fzf
            ./install --bin  --xdg     
            cp bin/* $LOCAL_DIR/bin/

        )
}

#########################
#      Other/Old        #
#########################


install_entr(){

    # check if installed
    if command -v entr &>/dev/null; then
        echo "entr is already installed."
        return
    fi

    git clone https://github.com/eradman/entr $REPO_DIR/entr

    (
        cd $REPO_DIR/entr
        ./configure 
        make
        PREFIX=$LOCAL_DIR make install
    )
}


# install_chruby():
# This function installs chruby, a Ruby version manager, on Linux and macOS.
# On Linux, it downloads and installs rbenv and chruby from GitHub.
# On macOS, it installs Homebrew if not already installed, and then installs chruby, ruby-install, and autojump using Homebrew.
# Finally, it sets up Ruby using ruby-install and activates chruby.
install_chruby() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Running on Linux"
        # Add Linux-specific code here

        cd $REPO_DIR
        curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash

        # Download chruby (-LO follows redirects and saves to file rather than stdout)
        curl -LO https://github.com/postmodern/chruby/releases/download/v0.3.9/chruby-0.3.9.tar.gz
        tar -xzvf chruby-0.3.9.tar.gz
        cd chruby-0.3.9/
        make install PREFIX=$REPO_DIR/chruby

    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "Running on macOS"
        # Install Homebrew if not installed
        if ! command -v brew &>/dev/null; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi

        # Install dependencies with Homebrew
        brew install chruby ruby-install autojump

        # Setup Ruby
        ruby-install ruby
        chruby ruby

    else
        echo "Unknown operating system"
        exit 1
    fi
}



install_zinit(){

    ZINIT_HOME="" bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"
    exec zsh
}


#########################
#      UTILITIES        #
#########################

start_ssh_agent() {
    eval $(ssh-agent -s)
    ssh-add
}