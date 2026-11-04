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

TARGET="$SCRIPT_DIR/target/home"

# target/home must be an exact copy of home/: rebuild it from scratch so files
# removed from the repo don't linger there
OLD_FILES="$(cd "$TARGET" 2>/dev/null && find . \( -type f -o -type l \) | sed 's#^\./##')"
rm -rf "$TARGET"
mkdir -p "$SCRIPT_DIR/target"
cp -fr "$SCRIPT_DIR/home" "$SCRIPT_DIR/target"

# ...and drop the $HOME symlinks (stowed earlier) to files that are gone, plus
# the directories left empty
printf '%s\n' "$OLD_FILES" | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ -e "$TARGET/$rel" ] || [ -L "$TARGET/$rel" ]; then
        continue
    fi
    link="$HOME/$rel"
    [ -L "$link" ] || continue
    case "$(readlink "$link")" in
        */target/home/"$rel")
            rm "$link"
            rmdir -p "$(dirname "$link")" 2>/dev/null
            ;;
    esac
done

ln -sfn "$SCRIPT_DIR/target/home/.zshrc.bootstrap" "$HOME/.zshrc.bootstrap"

BOOTSTRAP_LINE='[[ -s "$HOME/.zshrc.bootstrap" ]] && source "$HOME/.zshrc.bootstrap"'
if ! grep -qF "$BOOTSTRAP_LINE" "$HOME/.zshrc" 2>/dev/null; then
    echo "$BOOTSTRAP_LINE" >> "$HOME/.zshrc"
fi
