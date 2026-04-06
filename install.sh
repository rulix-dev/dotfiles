#!/bin/sh

RULIX_DEV_HOME=${HOME}/rulix-dev
if [ ! -d "$RULIX_DEV_HOME" ]; then
   mkdir -p "$RULIX_DEV_HOME"
fi

if [ ! -d "$RULIX_DEV_HOME/dotfiles" ]; then
    git clone https://github.com/rulix-dev/dotfiles.git "$RULIX_DEV_HOME/dotfiles"
fi


