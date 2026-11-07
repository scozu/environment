# Environment for every zsh shell (interactive, login, and non-interactive).
typeset -U path PATH
path=("$HOME/.local/bin" "$HOME/.opencode/bin" $path)
export PATH

# Machine-local overrides (untracked, gitignored)
[ -f ~/.zshenv.local ] && source ~/.zshenv.local
