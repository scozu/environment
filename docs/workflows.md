# Workflow Reference — ghost, silence, and the box

The operating manual for this environment. Refer back whenever something is
unclear; update it when workflows change.

## The machines

- **ghost** (Mac Studio) — always on. Owns: all projects, the OpenCode v2
  service, Postgres, the SSH host, Zed/Cursor remote servers. The
  compute/state machine.
- **silence** (MacBook Pro) — portable client. UIs run here; files, tools, and
  agent actions run on ghost. Can work offline via deliberate local clones.
  SSH-client only (Remote Login off): ghost cannot reach silence, so tool
  syncs and doctor parity checks run **from silence, against ghost**. Also
  runs the proofer web app (see Tailnet ports), so proof runs can go to
  either Mac.
- **the box** (Linux, Debian x86_64) — agent machine. Runs Claude Code with
  the pstack plugin, plus the OpenCode CLI; same Stow tree and pinned tool
  versions as the Macs (Linux builds via `scripts/sync-tools.sh`). No
  OpenCode service, no Postgres, no launchd. On the tailnet as `grokbox` via its
  own tailscaled, so `ssh ghost` and doctor's parity lines work once it is
  logged in. Repo at `~/Developer/environment`.

## The connective tissue

- **Tailscale**: private encrypted network. ghost = `ghost.tail483f5.ts.net`
  (IP `100.69.59.88`). MagicDNS gives the stable name.
- **SSH**: `ssh ghost` (alias in the stowed config; key auth, connection
  multiplexing, keepalive).
- **OpenCode service**: `https://ghost.tail483f5.ts.net:4096` — tailnet-only, TLS,
  HTTP basic auth (username `opencode`, password in ghost's
  `~/.config/opencode/service.json`).
- **Tailnet ports**: every app on the tailnet listens on `127.0.0.1` only and
  is reached through Tailscale Serve (HTTPS, tailnet-only, never Funnel).
  Each app gets one HTTPS port, the same on every machine that runs it, so an
  address differs between machines only by name. 443 (the bare address) is
  left unassigned so no app owns the front door; an app's HTTPS port matches
  its local port where it can. A new app takes the next free port in the table below,
  and gets a row in the same commit.

  | HTTPS port | App | Machines | Local port |
  | --- | --- | --- | --- |
  | 4096 | OpenCode service (launchd `ai.opencode.service`) | ghost | 4096 |
  | 8443 | proofer (studiopendleton/proofer, LaunchAgent `com.studiopendleton.proofer-web`) | ghost, silence | 8787 |
  | 8444+ | next free port | | |

- **Rex**: the one exception to the Serve rule. ghost's Rex (`Rex Beta.app`)
  is the session master and joins the tailnet as its own node, `rex`
  (`rex.tail483f5.ts.net`), using Rex's built-in Tailscale mode; the app's
  bundled server can't take the `--extra-listen tailnet-serve://` option that
  Serve needs. It only runs on ghost, so it is up exactly when ghost is.
  Other Macs (silence) run Rex with built-in Tailscale **off** and add `rex`
  as a remote server; sessions always live on ghost. The remote host is
  declared in the stowed `~/.config/rex/init.lua` (`rex.host`, label `rex`,
  skipped on ghost); apply with `rex config reload`.
  The node name has two parts and both must say `rex`:
  `rex server tailscale rename rex` renames the running node, but the app
  starts the node from its preference `rex.server.tailnet-hostname`, and
  when that is unset it uses `<computer>-rex` (`ghost-rex`), so a plain
  rename reverts on the next app restart. Set it once on ghost:
  `defaults write com.superlogical.rex rex.server.tailnet-hostname -string rex`.
  Check with `rex server status` (`tailscale: running · rex.tail483f5.ts.net`).

  Check with `tailscale serve status` on each machine. Only ghost is ever
  shared, never silence. People ghost is shared with get a grant for one
  app's port only (proofer: `tcp:8443`), never 443, and no other rule may
  match `autogroup:shared` (the default `"src": ["*"]` rule does), or the
  limit means nothing. The policy lives in the Tailscale admin console, not
  in this repo.

## Where things live

- **Repo**: `github.com/scozu/environment` (public, deliberately secrets-free).
  Stow package `home` → target `$HOME`:
  ```sh
  cd ~/Developer/environment && stow --no-folding -t "$HOME" home
  ```
- **Shared via Stow**: `.zshenv` (PATH), `.zshrc`, `~/.ssh/config`, Neovim
  baseline, Ghostty, Zed `settings.json`, OpenCode `opencode.jsonc`, Claude
  Code `~/.claude/settings.json`, and Cursor rules (`~/.cursor/rules/*.mdc`).
  `~/.claude` itself stays a real directory: sessions, projects, plugins,
  caches, and `settings.local.json` (per-machine overrides) never leave the
  machine.
- **Tools (no Homebrew)**: `~/.local/opt/<tool>/` + symlinks in
  `~/.local/bin` (PATH from `.zshenv`); Postgres data in
  `~/.local/var/postgres`. Install/update via the playbook in
  [tools.md](tools.md) — never edit PATH per tool.
- **Machine-local — NEVER committed or copied between machines**: SSH private
  keys, `known_hosts`, `authorized_keys`, OpenCode `service.json` + data
  (`~/.local/share/opencode`, `~/.local/state/opencode`), the launchd plist on
  ghost, app state, and the gitignored override files:
  `~/.zshrc.local` (aliases), `~/.zshenv.local` (env vars),
  `~/.ssh/config.local` (ssh overrides) — all auto-sourced by the stowed
  configs. Cursor app state is in this bucket too: `~/.cursor` caches,
  plugins, projects, extensions, `skills-cursor`, `argv.json` (per-machine
  crash-reporter id), `cli-config.json` (the CLI rewrites it), and
  `~/Library/Application Support/Cursor/User/` including its `settings.json`
  (the app rewrites it — never Stowed).

## Daily workflows

### 1. OpenCode (agent)

- **On ghost**: run `opencode` (TUI) or the desktop app — both auto-connect to
  the local service.
- **On silence (desktop)**: connect OpenCode Desktop to ghost over Tailscale.
  Verified working on 2026-10-19. In silence's terminal, run:
  ```sh
  ssh ghost 'opencode pair --url https://ghost.tail483f5.ts.net:4096'
  ```
  Paste the complete printed pairing link into the app's server address field.
  Links work once and expire after five minutes; never commit or share them.
  Open projects on ghost; no local service or SSH tunnel is needed.
- **On silence (TUI)**: `ocg` (alias defined in `~/.zshrc.local`) — TUI on silence,
  but the agent acts **on ghost**. Remember: the directory you launch `ocg`
  from is interpreted as a path on ghost, not silence.
- **From any Tailscale-connected device (browser)**:
  `https://ghost.tail483f5.ts.net:4096`, login `opencode` + password. Alternatively,
  generate a fresh pairing link with the command above and open it in the
  browser to sign in automatically.
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
- Only Cursor **rules** are shared: `~/.cursor/rules/*.mdc`, one symlink per
  file, stowed with `--no-folding` so parent directories stay real. `~/.cursor`
  itself is never a symlink; plugins, projects, and caches stay on the machine.
- Left unstowed on purpose, same call as OpenCode `cli.json`: anything Cursor
  or the CLI rewrites as state. That includes `User/settings.json` (commit
  `bef14ba` un-stowed it for this reason), `cli-config.json`, `argv.json`,
  `skills-cursor`, extension and plugin caches, and History / globalStorage /
  workspaceStorage. Editor settings and `remote.SSH.remotePlatform` for
  `ghost` live in that local `settings.json`; set them per machine.

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
   (Zed settings, Claude Code `settings.json`, Cursor `settings.json`,
   OpenCode `cli.json` — `cli.json` and Cursor `cli-config.json` are
   un-stowed for that reason). Commit real changes, `git restore` noise.
   The first time Cursor config is adopted on a machine, move any existing
   real file aside and stow; after that, pull updates the symlinks in place.
5. Machine-specific values go in the `.local` files, never in the repo.

### 6. The box (Linux)

- Bootstrap (once): system packages from apt — `zsh` (doctor and the stowed
  `.zshenv` need it), `make` (to build stow), `openssh-client`. Everything
  else follows the playbook: build stow 2.4.1 into `~/.local/opt/stow`, then
  `stow --no-folding -n -v -t "$HOME" home` → move conflicts aside as
  `<file>.pre-stow` → apply, then `scripts/sync-tools.sh`, then
  `scripts/doctor.sh`.
- `~/.ssh/config.local` on the box holds `IgnoreUnknown UseKeychain`: the
  shared `~/.ssh/config` uses the Apple-only `UseKeychain` option, which
  Linux OpenSSH rejects otherwise. `~/.ssh` must be mode 700.
- Tailscale: apt package from the official repo. PID 1 is not systemd, so
  start the daemon with `box-tailscaled` (machine-local script in
  `~/.local/bin`, idempotent; run it after a box restart), then once:
  `sudo tailscale up --hostname=grokbox --accept-dns=false --operator=box` and
  open the login URL it prints. `--accept-dns=false` leaves the box's
  resolver alone; `~/.ssh/config.local` adds `ProxyCommand tailscale nc %h %p`
  for `Host ghost`, so MagicDNS names resolve inside tailscaled. Fallback:
  the SOCKS5 proxy on `localhost:1055`. The box's key is `~/.ssh/id_ed25519`
  (comment `box`); add its `.pub` to `~/.ssh/authorized_keys` on ghost and
  silence.
- The box as a client: `~/.ssh/config.local` also has a full `Host silence`
  entry (`silence.tail483f5.ts.net`, user `scozu`, same ProxyCommand), so
  `ssh silence` works when silence is awake, on the tailnet, and has Remote
  Login on. HTTP to tailnet services (opencode `:4096`, proofer `:8443`)
  goes through the SOCKS5 proxy: `curl --socks5-hostname localhost:1055 …`,
  and run doctor as
  `ALL_PROXY=socks5h://localhost:1055 HTTPS_PROXY=socks5h://localhost:1055 scripts/doctor.sh`
  so its tailnet checks can resolve MagicDNS names.
- OpenCode on ghost from the box: `opencode run --server https://ghost.tail483f5.ts.net:4096 "<task>"`
  with `OPENCODE_PASSWORD` from `~/.config/opencode/ghost-server.env` (machine-local,
  mode 600). opencode's client (bun) can't use tailscaled's proxy, so
  `box-opencode-fwd` (machine-local, `~/.local/bin`, idempotent; run after a box
  restart) forwards `127.0.0.1:4096` to ghost via `tailscale nc`, and `/etc/hosts`
  maps `ghost.tail483f5.ts.net` to `127.0.0.1` so TLS names match. Sessions live
  on ghost's server and show up in the desktop and iOS apps.
- OpenCode: CLI only on the box, installed with the v2 installer (see the
  inventory in [tools.md](tools.md)). No service; the Stowed
  `opencode.jsonc` applies. `~/.bashrc` also puts `~/.opencode/bin` on PATH.
- Login shell stays bash; `~/.bashrc` already puts `~/.local/bin` first on
  PATH. The stowed `.zshenv` covers zsh and doctor.
- Pre-existing system copies (`/usr/bin/node`, `/usr/local/bin/{gh,bun,npm}`)
  are left alone; `~/.local/bin` shadows them.
- Rex: no Linux build yet. The stowed `~/.local/bin/rex` shim runs ghost's
  rex over `ssh ghost` (newest `RexServer/Versions/*`), so `rex ls`,
  `rex capture -s <session>`, `rex send` work from the box and `rex attach`
  works from an interactive terminal (`ssh -t` only when on a tty).
  `REX_SSH_HOST=<host>` targets another Mac. On the Macs the same file just
  execs the local rex. Doctor checks `rex ls` over ssh (warns if ghost is
  unreachable).
- Claude Code installs itself (native installer; self-updates are off via the
  shared `DISABLE_UPDATES=1`, upgrade with `claude install <version>`) to
  `~/.local/share/claude/versions/<ver>` with `~/.local/bin/claude` → that
  version; pstack comes from the `cursor-plugins` marketplace. Login is
  interactive and per machine; after it, run `/pstack:setup-pstack`.

### 7. Terminal / SSH

- `ssh ghost` — passwordless, fast (multiplexed).
- Copy files: `scp`/`rsync` over the alias; tunnels if ever needed:
  `ssh -L 4096:127.0.0.1:4096 ghost`.

## Rules that keep this working

1. Never commit secrets or app state (keys, `service.json`, auth, caches).
2. Machine-specific → `.local` override files (gitignored, auto-sourced).
3. Always Stow dry-run before real runs; review diffs before committing.
4. silence is a client: no local OpenCode service and no tool launchd jobs
   there. The one exception is app LaunchAgents listed under Tailnet ports
   (today the proofer).
5. The service password lives in one place: ghost's
   `~/.config/opencode/service.json`.
6. Tools follow the direct-install pattern. Every install or update goes
   through the playbook in [tools.md](tools.md) and updates its inventory in
   the same commit (tarball tools are scripted in `scripts/sync-tools.sh`);
   ghost, silence, and the box stay at the same versions (Postgres is
   ghost-only).
7. Tailnet apps listen on `127.0.0.1` and go through Tailscale Serve on the
   port in Tailnet ports. Never Funnel: it makes a page public.

## Status checks & maintenance

- OpenCode service: on ghost `opencode service status` (launchd job:
  `ai.opencode.service`).
- Postgres (ghost): start on demand — `pg_ctl -D ~/.local/var/postgres start`
  when working on the local app, `stop` when done. No launchd job by design;
  ghost-only.
- Tailscale proxy: `tailscale serve status`.
- SSH server: socket-activated — `ssh ghost 'echo ok'` is the test.
- Updates: opencode self-updates (its launchd job picks up new versions on
  restart), and the GUI apps (Zed, Cursor, Tailscale, ChatGPT) auto-update
  themselves. The tarball tools (nvim, pnpm, bun, node, gh) update via
  `scripts/sync-tools.sh`; stow and Postgres stay manual per
  [tools.md](tools.md) — pin the version and update the inventory there.
  Upstream drift is reported weekly on ghost; the log is
  `~/.local/var/check-upstream.log`, and `scripts/check-upstream.sh` runs it
  on demand.

## Known quirks / parked items

- Zed **OpenCode provider** (API key) path parked — console has no personal
  API keys yet; ACP covers it meanwhile.
- Neovim customization and Herdr: next stage, deliberately not started.
