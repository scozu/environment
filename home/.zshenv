# Environment for every zsh shell (interactive, login, and non-interactive).
typeset -U path PATH
path=("$HOME/.local/bin" "$HOME/.opencode/bin" $path)
export PATH

# rustup lives under ~/.local/opt/rustup; the proxies in ~/.local/bin
# (rustup, cargo, rustc, rustfmt, cargo-clippy, clippy-driver) need these
# so they don't fall back to ~/.rustup and ~/.cargo.
export RUSTUP_HOME="$HOME/.local/opt/rustup/rustup"
export CARGO_HOME="$HOME/.local/opt/rustup/cargo"

# Machine-local overrides (untracked, gitignored)
[ -f ~/.zshenv.local ] && source ~/.zshenv.local
