install_chruby() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "Running on Linux"
        # Add Linux-specific code here

        cd $REPO_DIR
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
        echo "Python is available. Installing Mackup..."
        pip install --upgrade mackup || pip3 install --upgrade mackup
    else
        echo "Python is not available."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            echo "Attempting to load Python module..."
            module load python || { echo "Failed to load Python module. Please ensure Python is installed."; }
        fi
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
