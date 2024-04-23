source variables


install_chruby() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Running on Linux"
        # Add Linux-specific code here

        cd $REPO_DIR
        curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash


        # Download chruby
        wget https://github.com/postmodern/chruby/releases/download/v0.3.9/chruby-0.3.9.tar.gz
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

install_mackup() {

    # Check for Python and install Mackup
    if command -v python &>/dev/null || command -v python3 &>/dev/null; then
        echo "Installing Mackup..."
        pip install --user --upgrade mackup || pip3 install --user --upgrade mackup
    else
        echo "Python is not available."
        
    fi

}

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


zsh_plugins() {
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    git clone https://github.com/zdharma-continuum/history-search-multi-word ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/history-search-multi-word
    git clone https://github.com/wfxr/forgit.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/forgit
    git clone https://github.com/agkozak/zsh-z ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-z

    git clone https://github.com/junegunn/fzf.git $REPO_DIR/fzf-git
    $REPO_DIR/fzf-git/install --all

    git clone https://github.com/wting/autojump $REPO_DIR/autojump
    cd $REPO_DIR/autojump
    chmod +x install.py
    ./install.py

}

install_zsh(){

    # clone the zsh repo
    git clone git://git.code.sf.net/p/zsh/code $REPO_DIR/zsh 
    cd $REPO_DIR/zsh

    # configure and install zsh
    ./configure --prefix=$HOME/.local
    make 
    make install 


}

install_gnustow(){

    cd $REPO_DIR
    wget https://ftp.gnu.org/gnu/stow/stow-latest.tar.gz

    tar -xzvf stow-latest.tar.gz
    # Extract the tarball
    rm stow-latest.tar.gz
    cd stow-2.4.0

     # configure and install zsh
    ./configure --prefix=$HOME/.local
    make 
    make install 
}