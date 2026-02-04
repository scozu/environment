# Environment Dotfiles

A unified dotfiles setup using GNU Stow for managing development environment configurations.

## What's Included

- **Shell**: zsh
- **Terminal**: Ghostty
- **Agents**: OpenCode
- **Editors**: Neovim, Zed

## Quick Setup

### Prerequisites

- GNU Stow: `brew install stow`
- Git (for cloning)

### Installation

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
   mv ~/.config/opencode ~/.config/opencode.backup
   mv ~/.config/zed ~/.config/zed.backup
   ```

3. **Create symlinks with Stow:**
   ```bash
   cd ~/Developer
   stow -t ~ environment
   ```

4. **Verify symlinks:**
   ```bash
   ls -la ~/.zshrc ~/.gitconfig ~/.config/nvim ~/.config/ghostty ~/.config/opencode ~/.config/zed
   ```

## Usage

- **Canonical source**: `~/Developer/environment/.config` is the source of truth
- **Edit configs**: Make changes in this repo and re-stow if needed
- **Version control**: Commit changes for reproducibility and sharing

## Management Commands

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

## Customization

### Adding New Configs

1. Copy config files to `~/Developer/environment/`
2. Remove originals from home directory  
3. Run `stow -R -t ~ environment` to create symlinks

### Sensitive Information

This repo is designed to be safe for public sharing:
- Uses GitHub no-reply email in `.gitconfig`
- No API keys, tokens, or passwords
- See `.gitignore` for excluded file types

For private configs, consider:
- Creating a separate private dotfiles repo
- Using environment variables for sensitive values
- Adding `.local` config files (already in `.gitignore`)

## File Structure

```
~/Developer/environment/
├── .config/
│   ├── ghostty/          # Terminal configuration
│   ├── nvim/             # Neovim configuration (kickstart.nvim)
│   ├── opencode/         # OpenCode configuration + themes
│   └── zed/              # Zed editor configuration (includes extensions)
├── .gitconfig            # Git configuration
├── .zshrc               # Zsh shell configuration
├── .gitignore           # Git ignore patterns
├── AGENTS.md            # AI assistant guidelines
└── README.md            # This file
```

## Dependencies

The configurations assume you have:
- **fzf**: For fuzzy finding (`brew install fzf`)
- **pure prompt**: Zsh prompt (`npm install -g pure-prompt`)
- **Neovim**: Modern vim (`brew install neovim`)
- **Ghostty**: Terminal emulator
- **Zed**: Modern code editor (https://zed.dev)
- **OpenCode**: OpenCode CLI (uses `~/.config/opencode`)

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
