# Vim motions in Shell
set -o vi

# fzf bindings in shell 
source <(fzf --zsh)

# prompt
autoload -U promptinit; promptinit
prompt pure

# alias
alias vi=nvim
alias vim=nvim
alias ls="ls -lathr --color=auto"
# alias ff='nvim $(fzf -m --preview="bat --color=always {}")'

# opencode
export PATH=/Users/scozu/.opencode/bin:$PATH
