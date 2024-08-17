# This script contains utility functions for installing various tools and dependencies.
# It includes functions for installing chruby, Mackup, Python, Zsh plugins, Zsh, GNU Stow, Rust, and Rust plugins.
# Each function checks the operating system and installs the necessary dependencies accordingly.
# The script also includes a function for restoring backups using GNU Stow.

# Note: This script assumes the presence of certain environment variables, such as $OSTYPE, $REPO_DIR, $DOTFILES_DIR, and $ZSH_CUSTOM.
# Make sure to set these variables appropriately before running the script.
source $HOME/dotfiles/scripts/exports.sh

#########################
#        ZSH            #
#########################

# zsh_plugins():
# This function clones various Zsh plugins from GitHub and installs them in the appropriate directory.
# It also clones the fzf repository and runs its installation script.

zsh_plugins() {
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    git clone https://github.com/zdharma-continuum/history-search-multi-word "$ZSH_CUSTOM/plugins/history-search-multi-word"
    git clone https://github.com/wfxr/forgit.git "$ZSH_CUSTOM/plugins/forgit"
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"


}

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
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    fi

}

# install_rust_plugins():
# This function installs various Rust plugins using Cargo, the Rust package manager.
# It first checks if Rust is installed, and then installs lsd, bat, and zoxide.
install_rust_plugins() {

    # Check if Rust is installed
    install_rust

    # Install lsd
    cargo install lsd

    # Install bat
    cargo install --locked bat

    # install z
    cargo install zoxide --locked

    # install tldr
    cargo install tlrc


    

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

    mkdir -p $HOME/local/lib/pkgconfig

    # configure and install 
    (
        cd $ncurses_dir
        ./configure --prefix=$LOCAL_DIR --with-shared --with-termlib --enable-pc-files --with-pkg-config-libdir=$HOME/local/lib/pkgconfig
        make
        make install
    )
}

install_tmux(){

    # check if installed
    if command -v tmux &>/dev/null; then
        echo "tmux is already installed."
        return
    fi

    # install dependencies
    install_libevent    
    install_ncurses


    # tmux install 

    git clone --depth 1 https://github.com/tmux/tmux.git $REPO_DIR/tmux

    (
        cd $REPO_DIR/tmux
        git fetch --unshallow
        ./autogen.sh
        PKG_CONFIG_PATH="$LOCAL_DIR/lib/pkgconfig" ./configure  --prefix=$LOCAL_DIR
        make
        make install 
    )


    # oh-my-tmux install
    git clone https://github.com/gpakosz/.tmux.git $REPO_DIR/oh-my-tmux
    mkdir -p "$CONFIG_DIR/tmux"
    ln -s "$REPO_DIR/oh-my-tmux/.tmux.conf" "$CONFIG_DIR/tmux/tmux.conf"

    # tpm install
    git clone https://github.com/tmux-plugins/tpm $REPO_DIR/tmux/plugins/tpm



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

        # Download chruby
        curl https://github.com/postmodern/chruby/releases/download/v0.3.9/chruby-0.3.9.tar.gz
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

# Function to source a file if it exists
# Arguments:
#   $1: The file path to be sourced
source_if_exists() {
    if [ -f "$1" ]; then
        source "$1"
    else 
        echo "File not found: $1"
    fi
}



install_zinit(){

    ZINIT_HOME="" bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"
    exec zsh
}