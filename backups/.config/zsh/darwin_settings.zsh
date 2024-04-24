export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
export PATH="${PATH:+${PATH}:}/opt/homebrew/opt/fzf/bin"


 plugins=($plugins brew macos)
# Homebrew Ruby setup
source $(brew --prefix)/opt/chruby/share/chruby/chruby.sh
source $(brew --prefix)/opt/chruby/share/chruby/auto.sh

# Ruby version management
chruby ruby-3.3.0

# source colorls
source $(dirname $(gem which colorls))/tab_complete.sh