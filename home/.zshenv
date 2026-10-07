# Environment for every zsh shell (interactive, login, and non-interactive).
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

# Machine-local overrides (untracked, gitignored)
[ -f ~/.zshenv.local ] && source ~/.zshenv.local
