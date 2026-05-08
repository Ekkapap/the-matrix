#!/usr/bin/env bash

echo "--- RTK Installer (Linux/macOS) ---"

if command -v brew >/dev/null 2>&1; then
    echo "[+] Homebrew found. Installing via brew..."
    brew install rtk
else
    echo "[!] Homebrew not found. Installing via official curl script..."
    curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
fi

if [ -f "$HOME/.zshrc" ]; then
    CONF_FILE="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
    CONF_FILE="$HOME/.bashrc"
else
    CONF_FILE="$HOME/.profile"
fi

echo "[+] Target config: $CONF_FILE"

RTK_PATH='export PATH="$HOME/.local/bin:$PATH"'
if ! grep -q ".local/bin" "$CONF_FILE"; then
    echo "" >> "$CONF_FILE"
    echo "$RTK_PATH" >> "$CONF_FILE"
    echo "[+] Path added to $CONF_FILE"
else
    echo "[*] Path already exists in $CONF_FILE"
fi

export PATH="$HOME/.local/bin:$PATH"

echo "--- Initializing RTK ---"
rtk --version
rtk init -g
rtk ls > /dev/null 2>&1
rtk gain

echo "--- RTK installed and is ready to use ---"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "[+] Opening RTK GitHub."
    open "https://github.com/rtk-ai/rtk"
fi
