#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$SCRIPT_DIR/target"
cp -fr "$SCRIPT_DIR/home" "$SCRIPT_DIR/target"

ln -sfn "$HOME/.zshrc.bootstrap" "$SCRIPT_DIR/target/home/.zshrc.bootstrap"

BOOTSTRAP_LINE='[[ -s "$HOME/.zshrc.bootstrap" ]] && source "$HOME/.zshrc.bootstrap"'
if ! grep -qF "$BOOTSTRAP_LINE" "$HOME/.zshrc" 2>/dev/null; then
    echo "$BOOTSTRAP_LINE" >> "$HOME/.zshrc"
fi
