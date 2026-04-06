
[[ -s "$HOME/.zshrc.bootstrap" ]] && source "$HOME/.zshrc.bootstrap"

[[ -s "$HOME/.zshrc.User" ]] && source "$HOME/.zshrc.User"

for f in "$HOME"/.zshrc.dd*; do
    [[ -s "$f" ]] && source "$f"
done

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Shell integrations
eval "$(fzf --zsh)"

# starship
eval "$(starship init zsh)"

# zoxide must be initialized last
eval "$(zoxide init --cmd cd zsh)"