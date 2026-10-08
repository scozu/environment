# Two-Mac Workflow Reference

The operating manual for this environment. Refer back whenever something is
unclear; update it when workflows change.

## The machines

- **ghost** (Mac Studio) — always on. Owns: all projects, the OpenCode v2
  service, the SSH host, Zed/Cursor remote servers. The compute/state machine.
- **silence** (MacBook Pro) — portable client. UIs run here; files, tools, and
  agent actions run on ghost. Can work offline via deliberate local clones.

## The connective tissue

- **Tailscale**: private encrypted network. ghost = `ghost.tail483f5.ts.net`
  (IP `100.69.59.88`). MagicDNS gives the stable name.
- **SSH**: `ssh ghost` (alias in the stowed config; key auth, connection
  multiplexing, keepalive).
- **OpenCode service**: `https://ghost.tail483f5.ts.net` — tailnet-only, TLS,
  HTTP basic auth (username `opencode`, password in ghost's
  `~/.config/opencode/service.json`).

## Where things live

- **Repo**: `github.com/scozu/environment` (public, deliberately secrets-free).
  Stow package `home` → target `$HOME`:
  ```sh
  cd ~/Developer/environment && stow --no-folding -t "$HOME" home
  ```
- **Shared via Stow**: `.zshenv` (PATH), `.zshrc`, `~/.ssh/config`, Neovim
  baseline, Ghostty, Zed `settings.json`, OpenCode `opencode.jsonc`, Cursor
  user `settings.json`, and Cursor rules (`~/.cursor/rules/*.mdc`).
- **Machine-local — NEVER committed or copied between machines**: SSH private
  keys, `known_hosts`, `authorized_keys`, OpenCode `service.json` + data
  (`~/.local/share/opencode`, `~/.local/state/opencode`), the launchd plist on
  ghost, app state, and the gitignored override files:
  `~/.zshrc.local` (aliases), `~/.zshenv.local` (env vars),
  `~/.ssh/config.local` (ssh overrides) — all auto-sourced by the stowed
  configs. Cursor app state is in this bucket too: `~/.cursor` caches,
  plugins, projects, extensions, `skills-cursor`, `argv.json` (per-machine
  crash-reporter id), `cli-config.json` (the CLI rewrites it), and
  `~/Library/Application Support/Cursor/User/` except `settings.json`.

## Daily workflows

### 1. OpenCode (agent)

- **On ghost**: run `opencode` (TUI) or the desktop app — both auto-connect to
  the local service.
- **On silence**: `ocg` (alias defined in `~/.zshrc.local`) — TUI on silence,
  but the agent acts **on ghost**. Remember: the directory you launch `ocg`
  from is interpreted as a path on ghost, not silence.
- **From anywhere (browser)**: `https://ghost.tail483f5.ts.net`, login
  `opencode` + password.
- The service runs under launchd on ghost (`ai.opencode.service`), survives
  reboots and client disconnects; all clients share the same sessions and
  data. On silence with no network, the service is unreachable — use local
  clones (below) instead.

### 2. Zed remote

- On silence: `ctrl-cmd-shift-o` → `ghost` (pre-pinned) → open a project.
  Files, language servers, tasks, and the integrated terminal all run on ghost.
- Reopen later: same dialog, or `zed ssh://ghost/~/Developer/...`.
- Browser previews: add `"port_forwards"` to the ghost `ssh_connections` entry.
- AI: `agent: new thread` → OpenCode (custom ACP agent, uses the local v2
  install). Zed stores the per-agent default model in `settings.json` — model
  switches show up as git diffs; commit real choices, restore noise.

### 3. Cursor remote

- On silence: Add repo → Use existing → **Connect via SSH** → `ghost`.
  Agents run on ghost ("remote machine" option). Cursor auto-installed its
  server on ghost (`~/.cursor-server`).
- Shared Cursor config is stowed the same way as Zed and Ghostty, with
  `--no-folding` so the parent directories stay real and the app can keep
  writing state beside the links:
  - `~/Library/Application Support/Cursor/User/settings.json` — editor
    settings, including `remote.SSH.remotePlatform` for `ghost`.
  - `~/.cursor/rules/*.mdc` — user rules, one symlink per file. `~/.cursor`
    itself is never a symlink; plugins, projects, and caches stay on the
    machine.
- Left unstowed on purpose, same call as OpenCode `cli.json`: anything Cursor
  or the CLI rewrites as state (`cli-config.json`, `argv.json`,
  `skills-cursor`, extension and plugin caches, History / globalStorage /
  workspaceStorage). A `keybindings.json` would be stowed next to
  `settings.json` if one is added later.

### 4. Working offline on silence

- Deliberate clone: `git clone git@github.com:scozu/<repo>.git` (GitHub as the
  hub) or `git clone ghost:~/path/to/repo` (direct from ghost over SSH).
- Work locally, commit, push; pull on ghost when back. Uncommitted changes
  don't sync — mind divergence between copies.

### 5. Editing shared config (the Stow loop)

1. Edit files under `~/Developer/environment/home/...` on either machine.
2. `stow --no-folding -n -t "$HOME" home` (dry run) → real run.
3. `git add/commit/push`; on the other machine: `git pull` (symlinks update
   in place — no re-stow needed).
4. `git status` habit: GUI apps rewrite their own files through symlinks
   (Zed settings, Cursor `settings.json`, OpenCode `cli.json` — `cli.json`
   and Cursor `cli-config.json` are un-stowed for that reason). Commit real
   changes, `git restore` noise. The first time Cursor config is adopted on
   a machine, move any existing real file aside and stow; after that, pull
   updates the symlinks in place.
5. Machine-specific values go in the `.local` files, never in the repo.

### 6. Terminal / SSH

- `ssh ghost` — passwordless, fast (multiplexed).
- Copy files: `scp`/`rsync` over the alias; tunnels if ever needed:
  `ssh -L 4096:127.0.0.1:4096 ghost`.

## Rules that keep this working

1. Never commit secrets or app state (keys, `service.json`, auth, caches).
2. Machine-specific → `.local` override files (gitignored, auto-sourced).
3. Always Stow dry-run before real runs; review diffs before committing.
4. silence is a client: no local OpenCode service, no launchd there.
5. The service password lives in one place: ghost's
   `~/.config/opencode/service.json`.

## Status checks & maintenance

- OpenCode service: on ghost `opencode service status` (launchd job:
  `ai.opencode.service`).
- Tailscale proxy: `tailscale serve status`.
- SSH server: socket-activated — `ssh ghost 'echo ok'` is the test.
- Updates: opencode self-updates (its launchd job picks up new versions on
  restart), Zed/Cursor/Tailscale auto-update themselves.

## Known quirks / parked items

- OpenCode **desktop app on silence** hits upstream auth bug (#51076) for
  non-loopback servers — use the TUI or web UI there until fixed.
- Zed **OpenCode provider** (API key) path parked — console has no personal
  API keys yet; ACP covers it meanwhile.
- Neovim customization and Herdr: next stage, deliberately not started.
