# Bootstrap `silence` — fresh macOS install, day 1

Goal: set up `silence` (MacBook Pro) from a **totally fresh macOS install** as a
clean client of this environment system. It replaces the old dotfiles flow —
nothing to back up on a wiped machine. Everything is deliberate, ordered, and
idempotent where possible.

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

## Step 0 — macOS basics

1. Finish the macOS setup assistant, create the user account (username does not
   matter — configs are `$HOME`-relative, and `User scozu` in the SSH config
   describes *ghost's* account, correct from any client).
2. Set the computer name to `silence` *before* installing Tailscale, so the
   Tailscale node gets the right name. Either System Settings → General →
   About → Name, or in Terminal with the trio of `scutil` commands (covers all
   three name slots — the GUI only sets the first):
   ```sh
   sudo scutil --set ComputerName "silence"
   sudo scutil --set LocalHostName "silence"
   sudo scutil --set HostName "silence"
   ```
   Verify:
   ```sh
   scutil --get ComputerName    # friendly name — this is the one Tailscale uses for the node
   scutil --get LocalHostName   # Bonjour .local name
   scutil --get HostName        # shell prompt / hostname
   ```
   New terminals pick the names up; no reboot required. (If Tailscale gets
   installed *before* the rename, fix the node name afterwards with
   `tailscale set --hostname silence`.)
3. Run Software Update until current.
4. Install Xcode Command Line Tools (needed for `git`, `make`, `cc`):
   ```sh
   xcode-select --install
   ```

## Step 1 — Tailscale from scratch

1. Download the macOS app from tailscale.com, install, sign in.
2. Verify: `tailscale status` shows `silence` and `ghost`;
   `ping -c1 ghost.tail483f5.ts.net` resolves (MagicDNS working).

## Step 2 — GUI apps

Download from official sites, drag to /Applications:

- Ghostty (ghostty.org)
- Zed (zed.dev)
- Cursor (cursor.com)

macOS Gatekeeper will block browser-downloaded apps on first open ("Apple could
not verify it is free of malware"). That is normal for direct downloads and
happens on ghost too. Approve each app once: right-click it in Finder →
**Open** → **Open** again in the dialog (or System Settings → Privacy &
Security → "Open Anyway"). Terminal fallback for stubborn cases:
`xattr -dr com.apple.quarantine "/Applications/<App>.app"`.
CLI tools downloaded with `curl` can trip the same check when the binary is
**unsigned** — Neovim's release binary is a known case (see Step 3).

Remote Login on silence is NOT needed — it is only a client.

## Step 3 — CLI tools (direct installs, mirroring ghost)

```sh
mkdir -p ~/.local/bin ~/.local/opt

# Until Stow applies .zshenv, export the PATH for this session FIRST —
# otherwise newly installed commands are invisible to this shell:
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

# GNU Stow (build from source — this is the tricky one)
curl -O https://ftp.gnu.org/gnu/stow/stow-latest.tar.gz
tar xzf stow-latest.tar.gz && cd stow-*/
./configure --prefix="$HOME/.local/opt/stow" && make && make install
ln -s "$HOME/.local/opt/stow/bin/stow" "$HOME/.local/bin/stow"
cd .. && stow --version                      # expect 2.4.x

# Neovim (arch-matched release tarball)
uname -m                                     # arm64 = Apple Silicon, x86_64 = Intel
curl -LO "https://github.com/neovim/neovim/releases/latest/download/nvim-macos-$(uname -m).tar.gz"
tar xzf "nvim-macos-$(uname -m).tar.gz"
mv "nvim-macos-$(uname -m)" "$HOME/.local/opt/nvim"
ln -s "$HOME/.local/opt/nvim/bin/nvim" "$HOME/.local/bin/nvim"
# Neovim's release binary is unsigned → macOS blocks the first run
# ("Apple could not verify ..."). Approve once: run `nvim --version` (blocked),
# then System Settings → Privacy & Security → "Allow Anyway", then run again.
# Terminal alternative:
#   xattr -d com.apple.provenance ~/.local/opt/nvim/bin/nvim

# OpenCode CLI (official installer, same as ghost → ~/.opencode/bin)
curl -fsSL https://opencode.ai/install | bash

# pnpm (pinned release tarball — NOT the curl installer, which would install
# to ~/Library/pnpm and edit shell env files; this keeps the direct-install pattern)
PNPM_VERSION=12.10.1
ARCH=$(uname -m | sed 's/x86_64/x64/')
rm -rf "$HOME/.local/opt/pnpm"
mkdir -p "$HOME/.local/opt/pnpm"
curl -fL -o "/tmp/pnpm-$PNPM_VERSION.tar.gz" \
  "https://github.com/pnpm/pnpm/releases/download/v$PNPM_VERSION/pnpm-darwin-$ARCH.tar.gz"
tar -xzf "/tmp/pnpm-$PNPM_VERSION.tar.gz" -C "$HOME/.local/opt/pnpm"
ln -sf "$HOME/.local/opt/pnpm/pnpm" "$HOME/.local/bin/pnpm"

stow --version && nvim --version | head -1 && opencode --version && pnpm --version
```

## Step 4 — SSH key for silence (machine-local)

```sh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519   # no passphrase, or one + keychain
```

- Add the `.pub` to **GitHub** (for cloning/pushing): Settings → SSH keys.
- Add the `.pub` to **ghost's `authorized_keys`** (needed before Stow, since the
  `ghost` alias lives in the repo). Either:
  - from silence, with password auth (Remote Login is on ghost):
    `ssh scozu@ghost.tail483f5.ts.net 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys' < ~/.ssh/id_ed25519.pub`
  - or paste the `.pub` into a terminal on ghost:
    `cat >> ~/.ssh/authorized_keys` (then paste, ctrl-D).

## Step 5 — clone the repo and Stow

```sh
git config --global user.name "Jason Scholtz"
git config --global user.email "33293669+scozu@users.noreply.github.com"

mkdir -p ~/Developer
git clone git@github.com:scozu/environment.git ~/Developer/environment
cd ~/Developer/environment
stow --no-folding -n -v -t "$HOME" home   # DRY RUN — read it carefully
stow --no-folding -v -t "$HOME" home      # real run (fix any leftover conflicts)
mkdir -p ~/.ssh/control && chmod 700 ~/.ssh/control   # for SSH multiplexing
```

- If the dry run reports conflicts with anything in `$HOME`, resolve them.
  A fresh install has none, unless Cursor was opened in Step 2. That launch
  writes `~/Library/Application Support/Cursor/User/settings.json`. Move that
  file aside, then stow. The package copy replaces it.
- Create local override files only if needed (they are gitignored and sourced
  automatically by the stowed `.zshrc`/`.zshenv`):
  `~/.zshrc.local` (aliases), `~/.zshenv.local` (env vars), `~/.ssh/config.local`.

## Step 6 — verify each layer, in order

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
6. **Cursor v3**: quit Cursor fully and reopen so it reads the stowed user
   settings and rules. Add repo → Use existing → Connect via SSH → `ghost` →
   select `~/Developer/…`. Agents then run on ghost ("remote machine" option).
   `remote.SSH.remotePlatform` for `ghost` is already in the stowed
   `settings.json`. `~/.cursor` stays a real directory (`--no-folding`);
   only `settings.json` and files under `~/.cursor/rules/` are links.
7. **Git**: `git config --global user.name && git config --global user.email`
   should show the identity from Step 5.

## Step 7 — clean up

- Live with it for a few days before deleting anything from the setup.
- Never copy secrets or machine state from ghost; if something needs to be
  machine-specific, use the `.local` override files (gitignored) or
  `~/.ssh/config.local`.

## Troubleshooting notes

- `ssh ghost` prompts for a password → key not in ghost's `authorized_keys`,
  or wrong key being offered (`IdentitiesOnly yes` fixes the latter).
- OpenCode client 401 → wrong/missing `OPENCODE_SERVER_PASSWORD`.
- Zed custom ACP agent "command not found" → Zed was started before the
  `.zshenv` PATH change; quit Zed fully and reopen. Check `dev: open acp logs`.
- Stow conflict → the item still exists in `$HOME`; move it out of the way.
- `git status` in the environment repo shows edits you didn't make → a GUI app
  rewrote a stowed file (known behavior for Zed/OpenCode state fields); review
  the diff, commit real choices, `git restore` noise.
