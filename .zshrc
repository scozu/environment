# Vim motions in Shell
set -o vi

# fzf bindings in shell 
source <(fzf --zsh)

# prompt
autoload -U promptinit; promptinit
prompt pure

# alias
alias v=nvim
alias vi=nvim
alias vim=nvim
alias ls="ls -lah --color=auto"
# alias ff='nvim $(fzf -m --preview="bat --color=always {}")'

# opencode
export PATH=/Users/scozu/.opencode/bin:$PATH

# bun completions
[ -s "/Users/scozu/.bun/_bun" ] && source "/Users/scozu/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
