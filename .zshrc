# Vim motions in Shell
set -o vi

# Initialize TTY-bound shell UI only when a real terminal is attached.
# Some app sidecars spawn interactive shells without ZLE support.
if [[ -o interactive && -t 1 ]]; then
  # fzf bindings in shell
  source <(fzf --zsh)

  # prompt
  autoload -U promptinit; promptinit
  prompt pure
fi

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

# OpenClaw Completion
source "/Users/scozu/.openclaw/completions/openclaw.zsh"

# Omarchy-like terminal workflow
alias c='opencode'

n() {
  if [ "$#" -eq 0 ]; then
    command nvim .
  else
    command nvim "$@"
  fi
}

t() {
  "$HOME/Developer/environment/scripts/tmux-workspace.sh"
}

treset() {
  "$HOME/Developer/environment/scripts/tmux-workspace.sh" --reset-layout
}
