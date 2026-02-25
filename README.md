# Environment Dotfiles

Dotfiles setup using Stow. Yes, everything is in `~/Developer` just to get the fancy little Finder icon.

- **Shell**: zsh
- **Terminal**: Ghostty
- **Multiplexer**: tmux
- **Agents**: OpenCode
- **Editors**: Neovim, Zed

## Installation

1. **Clone this repository:**
   ```bash
   git clone <your-repo-url> ~/Developer/environment
   cd ~/Developer/environment
   ```

2. **Backup existing configs (optional):**
   ```bash
   mv ~/.zshrc ~/.zshrc.backup
   mv ~/.gitconfig ~/.gitconfig.backup
   mv ~/.config/nvim ~/.config/nvim.backup
    mv ~/.config/ghostty ~/.config/ghostty.backup
    mv ~/.config/tmux ~/.config/tmux.backup
    mv ~/.config/opencode ~/.config/opencode.backup
   mv ~/.config/zed ~/.config/zed.backup
   mv ~/.ssh/config ~/.ssh/config.backup
   ```

3. **Create symlinks with Stow:**
   ```bash
   cd ~/Developer
   stow -t ~ environment
   ```

4. **Verify symlinks:**
   ```bash
   ls -la ~/.zshrc ~/.gitconfig ~/.config/nvim ~/.config/ghostty ~/.config/tmux ~/.config/opencode ~/.config/zed ~/.ssh/config
   ```

## Tmux

- Entry command: `t` (attach to `dev`, or create it)
- Reset/rebuild layout: `treset`
- Default session/window: `dev` / `environment`
- New page/window: `Ctrl+Space` then `c` (creates a new `environment` window with `nvim`, `opencode`, and a bottom shell pane)
- Default layout:
  - left pane: `nvim`
  - right pane: `opencode`
  - bottom pane: terminal shell (default `TMUX_BOTTOM_LINES=15`)

### Management Commands

```bash
# Create symlinks
cd ~/Developer && stow -t ~ environment

# Remove symlinks
cd ~/Developer && stow -D -t ~ environment

# Re-create symlinks (useful after updates)
cd ~/Developer && stow -R -t ~ environment

# Check what would be symlinked (dry run)
cd ~/Developer && stow -n -v -t ~ environment
```

### Adding New Configs

1. Copy config files to `~/Developer/environment/`
2. Remove originals from home directory  
3. Run `stow -R -t ~ environment` to create symlinks

## Troubleshooting

**Symlinks not working?**
- Ensure you're running stow from `~/Developer`
- Check target directory with `stow -n -v -t ~ environment`

**Configs not loading?**
- Restart your shell: `exec zsh`
- Check symlink targets: `ls -la ~/.zshrc`

**Want to start fresh?**
- Remove symlinks: `stow -D -t ~ environment`
- Delete and re-clone repository
- Re-run setup steps
