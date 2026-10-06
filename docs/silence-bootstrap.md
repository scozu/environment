# Bootstrap `silence` — replace its dotfiles with this system

Goal: make `silence` (MacBook Pro) a clean client of this environment system,
replacing whatever dotfiles setup it currently has. Everything below is
deliberate, ordered, and safe (nothing is deleted — old configs are moved to a
backup folder first).

## Facts this system relies on

- `ghost` (Mac Studio) is the compute/state machine. Always on.
- SSH: `ssh ghost` resolves via Tailscale MagicDNS (`ghost.tail483f5.ts.net`,
  user `scozu` on ghost). Key auth + connection multiplexing.
- OpenCode v2 **service** runs ONLY on ghost:
  `https://ghost.tail483f5.ts.net` (tailnet-only, TLS, basic auth).
  `silence` is a **client** — do NOT install a local service/launchd agent.
- Repo: `git@github.com:scozu/environment.git`; Stow package `home`, target `$HOME`.
- Tools are direct-installed to `~/.local/opt/…` and symlinked into
  `~/.local/bin` (matching ghost). Homebrew is not required.
- Machine-local (NEVER copy these from ghost): `~/.ssh` keys, `known_hosts`,
  `authorized_keys`, OpenCode `service.json`/auth/data dirs, launchd plists,
  app state. `silence` generates its own key and gets its own copies.

## Step 0 — power on, Tailscale, identity

1. Power on, join network. Confirm Tailscale: `tailscale status` should show
   `ghost`, `silence`, `wraith`. Confirm MagicDNS:
   `ping -c1 ghost.tail483f5.ts.net`.
2. Set git identity (same as ghost):
   ```sh
   git config --global user.name "Jason Scholtz"
   git config --global user.email "33293669+scozu@users.noreply.github.com"
   ```
3. Note the local username (`whoami`) — irrelevant to the configs: everything is
   `$HOME`-relative, and `User scozu` in the SSH config describes *ghost's*
   account, which is correct from any client.

## Step 1 — preserve the old dotfiles system (backup, not delete)

1. Make a timestamped backup dir: `mkdir -p ~/dotfiles-backup-$(date +%Y%m%d)`.
2. If the old system is GNU Stow-based: find its repo and run
   `stow -D -t "$HOME" <packages>` inside it first (unstow), so no stale
   symlinks remain.
3. Move every old config file/dir into the backup dir (they must not stay in
   place or they will conflict with Stow later). Typical candidates:
   `~/.zshrc`, `~/.zshenv`, `~/.zprofile`, `~/.gitconfig`, `~/.ssh/config`,
   `~/.config/nvim`, `~/.config/zed`, `~/.config/ghostty`, `~/.config/opencode`,
   `~/.vimrc`, `~/.tmux.conf`, etc.
4. Leave `~/.ssh/` itself in place if it already has keys you want to keep — but
   this system expects a fresh `~/.ssh/id_ed25519` (generate in Step 3). Old
   `authorized_keys`/`known_hosts` can stay local; they are never shared.

## Step 2 — direct-install the CLI tools (mirror ghost)

Pattern: install to `~/.local/opt/<tool>`, symlink into `~/.local/bin`.

1. **GNU Stow** (needed first):
   ```sh
   curl -O https://ftp.gnu.org/gnu/stow/stow-latest.tar.gz
   tar xzf stow-latest.tar.gz && cd stow-*/
   ./configure --prefix="$HOME/.local/opt/stow" && make && make install
   ln -s "$HOME/.local/opt/stow/bin/stow" "$HOME/.local/bin/stow"
   ```
2. **Neovim** (match `uname -m`: arm64 = Apple Silicon, x86_64 = Intel):
   ```sh
   curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-macos-$(uname -m).tar.gz
   tar xzf nvim-macos-$(uname -m).tar.gz
   mv nvim-macos-$(uname -m) "$HOME/.local/opt/nvim"
   ln -s "$HOME/.local/opt/nvim/bin/nvim" "$HOME/.local/bin/nvim"
   ```
3. **OpenCode CLI** (same installer as ghost → `~/.opencode/bin/opencode`):
   ```sh
   curl -fsSL https://opencode.ai/install | bash
   opencode --version   # expect 2.0.23 or newer, matching ghost
   ```
4. **Apps** (drag to /Applications): Zed (zed.dev), Cursor (cursor.com),
   Ghostty (ghostty.org).

## Step 3 — SSH key for silence (machine-local)

```sh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519   # no passphrase, or one + keychain
```

- Add the `.pub` to **GitHub** (for cloning/pushing): Settings → SSH keys.
- Add the `.pub` to **ghost's `authorized_keys`** (needed before Stow, since the
  `ghost` alias lives in the repo). Either:
  - from silence, with password auth (Remote Login is on):
    `ssh scozu@ghost.tail483f5.ts.net 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys' < ~/.ssh/id_ed25519.pub`
  - or paste the `.pub` into a terminal on ghost:
    `cat >> ~/.ssh/authorized_keys` (then paste, ctrl-D).

## Step 4 — clone the repo and Stow

```sh
mkdir -p ~/Developer
git clone git@github.com:scozu/environment.git ~/Developer/environment
cd ~/Developer/environment
stow --no-folding -n -v -t "$HOME" home   # DRY RUN — read it carefully
stow --no-folding -v -t "$HOME" home      # real run (fix any leftover conflicts)
mkdir -p ~/.ssh/control && chmod 700 ~/.ssh/control   # for SSH multiplexing
```

- If the dry run reports conflicts with anything still in `$HOME`, move that
  item to the backup dir and re-run.
- Create local override files only if needed (they are gitignored):
  `~/.zshrc.local`, `~/.zshenv.local`, `~/.ssh/config.local`.

## Step 5 — verify each layer, in order

1. `zsh -c 'command -v stow nvim opencode'` — all three resolve (PATH from `.zshenv`).
2. `ssh ghost 'echo ok'` — passwordless, key auth.
3. Stow dry run is clean: `stow --no-folding -n -t "$HOME" home`.
4. **OpenCode client → ghost service** (password lives on ghost:
   `~/.config/opencode/service.json`). One-liner from silence:
   ```sh
   OPENCODE_SERVER_PASSWORD='<password from ghost>' opencode --server https://ghost.tail483f5.ts.net
   ```
   Convenience (machine-local, untracked — never commit) in `~/.zshrc.local`:
   ```sh
   export OPENCODE_SERVER_PASSWORD='<password from ghost>'
   alias ocg='opencode --server https://ghost.tail483f5.ts.net'
   ```
   Smoke test: `curl -u opencode:$OPENCODE_SERVER_PASSWORD https://ghost.tail483f5.ts.net/api/info` → 200.
   Sessions are shared: anything created here appears in ghost's TUI too.
   (The desktop app on silence hits a known upstream auth bug for non-loopback
   servers — use the CLI TUI/web for now, or the fix when it ships.)
5. **Zed remote**: restart Zed (so it picks up the stowed settings + shell
   PATH). `ctrl-cmd-shift-o` → `ghost` should already be listed (pre-pinned in
   settings) → open a project. Verify: Zed's terminal `hostname` → `ghost`;
   language servers appear in ghost's process list. ACP: start an OpenCode
   thread (`agent: new thread`) — the custom v2 agent config is already stowed.
   Optional port forwarding for a dev server on ghost:
   `"port_forwards": [{ "local_port": 8080, "remote_port": 3000 }]` inside the
   ghost `ssh_connections` entry.
6. **Cursor v3**: Add repo → Use existing → Connect via SSH → `ghost` →
   select `~/Developer/…`. Agents then run on ghost ("remote machine" option).
7. **Git**: `git config --global user.name && git config --global user.email`
   should show the identity from Step 0.

## Step 6 — clean up

- Live with it for a few days, then delete `~/dotfiles-backup-…`.
- Never copy secrets or machine state from ghost; if something needs to be
  machine-specific, use the `.local` override files (gitignored) or
  `~/.ssh/config.local`.

## Troubleshooting notes

- `ssh ghost` prompts for a password → key not in ghost's `authorized_keys`,
  or wrong key being offered (`IdentitiesOnly yes` fixes the latter).
- OpenCode client 401 → wrong/missing `OPENCODE_SERVER_PASSWORD`.
- Zed custom ACP agent "command not found" → Zed was started before the
  `.zshenv` PATH change; quit Zed fully and reopen. Check `dev: open acp logs`.
- Stow conflict → the item still exists in `$HOME`; move it to the backup dir.
- `git status` in the environment repo shows edits you didn't make → a GUI app
  rewrote a stowed file (known behavior for Zed/OpenCode state fields); review
  the diff, commit real choices, `git restore` noise.
