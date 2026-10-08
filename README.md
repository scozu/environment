# Apply this environment

This repo is the shared config for ghost and silence. The Stow package is `home`. The target is `$HOME`. Stow links each shared file. Secrets and app state stay on the machine that created them.

## Stow the package

Run the dry run, read it, then run Stow for real.

```sh
cd ~/Developer/environment
stow --no-folding -n -t "$HOME" home
stow --no-folding -t "$HOME" home
```

`--no-folding` links files and leaves parent directories real. `~/.cursor` and `~/Library/Application Support/Cursor/User` must stay real directories. Cursor writes caches and session state into them.

If the dry run reports a conflict, move that file out of `$HOME` and run Stow again.

## Edit shared files

Edit the copy under `home/` in this repo. A GUI may rewrite a linked file such as Zed or Cursor `settings.json`. Commit a real setting change. Run `git restore` on edits you did not mean to keep.

- `~/.zshenv` and `~/.zshrc` source `~/.zshenv.local` and `~/.zshrc.local` when those files exist.
- `~/.ssh/config` includes `~/.ssh/config.local` when that file exists.
- Neovim config under `~/.config/nvim/`.
- `~/.config/ghostty/config.ghostty`
- `~/.config/zed/settings.json`
- `~/.config/opencode/opencode.jsonc`
- `~/Library/Application Support/Cursor/User/settings.json`
- Rule files under `~/.cursor/rules/`. The current file is `pstack-models.mdc`.

`git pull` updates a link that already exists. On a machine that does not have the link yet, run Stow after the pull.

## Keep machine-local files out

Do not commit these. `.gitignore` blocks the copies that would land inside `home/`.

- SSH private keys, `known_hosts`, and `authorized_keys`.
- `~/.zshrc.local`, `~/.zshenv.local`, and `~/.ssh/config.local`.
- OpenCode `service.json`, `cli.json`, and the data under `~/.local/share/opencode`.
- Cursor `argv.json`. It holds this machine's crash-reporter id.
- Cursor `cli-config.json`. The CLI rewrites it.
- Cursor plugins, extensions, `skills-cursor`, project caches, History, globalStorage, and workspaceStorage.

To share keybindings later, add `keybindings.json` next to `settings.json` in the package and stow it the same way.

## Check this machine

Run `scripts/doctor.sh` from the repo. A clean run means the Stow tree has no pending links and the checks for this machine passed.

## Read the longer docs

[Bootstrap silence](docs/silence-bootstrap.md) is the fresh-install sequence.

[Two-Mac workflow](docs/workflows.md) is the operating manual.
