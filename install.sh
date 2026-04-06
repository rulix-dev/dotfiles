#!/bin/sh

RULIX_DEV_HOME=${HOME}/rulix-dev
if [ ! -d "$RULIX_DEV_HOME" ]; then
   mkdir -p "$RULIX_DEV_HOME"
fi

if [ ! -d "$RULIX_DEV_HOME/dotfiles" ]; then
    git clone https://github.com/rulix-dev/dotfiles.git "$RULIX_DEV_HOME/dotfiles"
fi
git -C "$RULIX_DEV_HOME/dotfiles" pull


mkdir -p $RULIX_DEV_HOME/dotfiles/target
cp -fr $RULIX_DEV_HOME/dotfiles/home $RULIX_DEV_HOME/dotfiles/target

BOOTSTRAP_LINE='[[ -s "$HOME/.zshrc.bootstrap" ]] && source "$HOME/.zshrc.bootstrap"'
if ! grep -qF "$BOOTSTRAP_LINE" "$HOME/.zshrc" 2>/dev/null; then
    echo "$BOOTSTRAP_LINE" >> "$HOME/.zshrc"
fi