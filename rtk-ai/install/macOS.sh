#!/bin/zsh
brew install rtk
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
export PATH="$HOME/.local/bin:$PATH"
rtk --version
rtk init -g
rtk ls > /dev/null 2>&1
rtk gain
