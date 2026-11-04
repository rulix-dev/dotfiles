#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

FORCE=0
for arg in "$@"; do
    case "$arg" in
        -f|--force) FORCE=1 ;;
        *) echo "usage: $0 [-f|--force]" >&2; exit 1 ;;
    esac
done

# --force: drop the sentinel so the next shell re-runs the one-time setup
# (__rulix_dev_zsh_setup in .zshrc.bootstrap)
if [ "$FORCE" = 1 ]; then
    rm -f "$HOME/.zshrc.setup"
fi

mkdir -p "$SCRIPT_DIR/target"
cp -fr "$SCRIPT_DIR/home" "$SCRIPT_DIR/target"

ln -sfn "$SCRIPT_DIR/target/home/.zshrc.bootstrap" "$HOME/.zshrc.bootstrap"

BOOTSTRAP_LINE='[[ -s "$HOME/.zshrc.bootstrap" ]] && source "$HOME/.zshrc.bootstrap"'
if ! grep -qF "$BOOTSTRAP_LINE" "$HOME/.zshrc" 2>/dev/null; then
    echo "$BOOTSTRAP_LINE" >> "$HOME/.zshrc"
fi
