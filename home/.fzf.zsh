# Setup fzf
# ---------
if [[ ! "$PATH" == */Users/raul.perezclavero/.fzf/bin* ]]; then
  PATH="${PATH:+${PATH}:}/Users/raul.perezclavero/.fzf/bin"
fi

source <(fzf --zsh)
