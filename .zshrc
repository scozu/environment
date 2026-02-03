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
 # Colors and color-aware ls with cross-platform support
 if command -v gls >/dev/null 2>&1; then
   alias ls="gls -lah --color=auto"
 elif command -v ls >/dev/null 2>&1 && ls --color=auto >/dev/null 2>&1; then
   alias ls="ls -lah --color=auto"
 else
   if ls -G >/dev/null 2>&1; then
       alias ls="ls -lahG"
   else
       alias ls="ls -lah"
   fi
 fi
 # macOS/BSD-friendly color config (enable CLI coloring)
 export CLICOLOR=1
 export LSCOLORS=GxFxCxDxBxegedabagacad
 # alias ff='nvim $(fzf -m --preview="bat --color=always {}")'

# opencode
export PATH=/Users/scozu/.opencode/bin:$PATH

# bun completions
[ -s "/Users/scozu/.bun/_bun" ] && source "/Users/scozu/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
