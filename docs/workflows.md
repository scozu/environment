# Workflow Reference — ghost, silence, and the box

The operating manual for this environment. Refer back whenever something is
unclear; update it when workflows change.

## The machines

- **ghost** (Mac Studio) — always on. Owns: all projects, the OpenCode v2
  service, Postgres, the SSH host, Zed/Cursor remote servers. The
  compute/state machine.
- **silence** (MacBook Pro) — portable client. UIs run here; files, tools, and
  agent actions run on ghost. Can work offline via deliberate local clones.
  ghost manages silence over SSH (`ssh silence` works non-interactively, see
  Terminal / SSH below), so tool syncs and doctor parity checks run **from
  ghost**. Also runs the proofs web app (see Tailnet ports), so proof runs can
  go to either Mac.
- **the box** (Linux, Debian x86_64) — agent machine. Runs Claude Code with
  the pstack plugin, plus the OpenCode CLI; same Stow tree and pinned tool
  versions as the Macs (Linux builds via `scripts/sync-tools.sh`). No
  OpenCode service, no Postgres, no launchd, and no local tailscale or
  tailscaled. Tailnet access comes from Grok Bot's Tailscale connector,
  authenticated in the Grok Bot app. From the box, address tailnet hosts by
  their full MagicDNS name (`ghost.tail483f5.ts.net`,
  `silence.tail483f5.ts.net`) over HTTPS.
  Short-name DNS from the shell isn't promised. The box's shell egress is
  an HTTP proxy, so HTTPS to tailnet names works and SSH does not: the box
  works on ghost through the ghost-env MCP server (see "The box and ghost"
  below). Repo at `~/Developer/environment`.

## The connective tissue

- **Tailscale**: private encrypted network. ghost = `ghost.tail483f5.ts.net`
  (IP `100.69.59.88`), silence = `silence.tail483f5.ts.net`. MagicDNS gives
  the stable name. The box reaches those hosts through Grok Bot's Tailscale
  connector, not a local Tailscale client.
- **SSH**: `ssh ghost` (alias in the stowed config; key auth, connection
  multiplexing, keepalive).
- **OpenCode service**: `https://ghost.tail483f5.ts.net:4096` — tailnet-only, TLS,
  HTTP basic auth (username `opencode`, password in ghost's
  `~/.config/opencode/service.json`).
- **Tailnet ports**: every app on the tailnet listens on `127.0.0.1` only and
  is reached through Tailscale Serve (HTTPS, tailnet-only, never Funnel).
  Each app gets one HTTPS port, the same on every machine that runs it, so an
  address differs between machines only by name. 443 (the bare address) is
  ghost-only and reserved for envd, the ghost-env MCP server the box uses;
  envd checks each caller with `tailscale whois`, so the bare address is not
  an open front door. Every other app's HTTPS port matches its local port
  where it can. A new app takes the next free port in the table below,
  and gets a row in the same commit.

  | HTTPS port | App | Machines | Local port |
  | --- | --- | --- | --- |
  | 443 | envd / ghost-env MCP (LaunchAgent `dev.scozu.envd`) | ghost | 8790 |
  | 4096 | OpenCode service (launchd `ai.opencode.service`) | ghost | 4096 |
  | 8443 | proofs (studiopendleton/proofs, LaunchAgent `com.studiopendleton.proofs-web`) | ghost, silence | 8787 |
  | 8444+ | next free port | | |

- **Rex**: the one exception to the Serve rule. Every Mac is both a Rex
  client and a Rex server: each Mac's Rex (`Rex Beta.app`) joins the tailnet
  as its own node `<mac>-rex` using Rex's built-in Tailscale mode
  (`ghost-rex.tail483f5.ts.net`, `silence-rex.tail483f5.ts.net`); the app's
  bundled server can't take the `--extra-listen tailnet-serve://` option that
  Serve needs. These are separate devices from the system Tailscale nodes
  `ghost` and `silence`, which is why the Rex nodes can't take those names.
  Sessions live on the Mac that runs them and are reachable only while that
  Mac is awake and online (a sleeping silence means `rex -S silence` fails).
  Remote hosts are added **in the app** (Settings > Remote Hosts, Add
  Remote Host…), not in `~/.config/rex/init.lua`: the app lists only hosts
  added in the app (it mirrors them into its server, so `rex hosts` and
  `rex -S <label>` see them as "stored"), never `rex.host` entries, and it
  rejects an app host whose label init.lua already declares (409 conflict).
  On ghost add `silence` → `https://silence-rex.tail483f5.ts.net`; on silence
  add `ghost` → `https://ghost-rex.tail483f5.ts.net`. Doctor warns if the
  other Mac's host is missing. ghost's Rex can reach silence's
  Rex: a Rex connection can do anything that server
  can, including starting programs as scozu.
  Access stays owner-only (admin@jasonscholtz.net): **never** enable
  `--allow-tailnet-members` (or the app's tailnet-members toggle) or
  `--allow-anonymous`.
  The node name has two parts and both must say `<mac>-rex`:
  `rex server tailscale rename <mac>-rex` renames the running node (and
  `rex server tailscale on --hostname <mac>-rex` enables a new one; it is
  runtime-only), but the app starts the node from its preference
  `rex.server.tailnet-hostname`. Set it once per Mac:
  `defaults write com.superlogical.rex rex.server.tailnet-hostname -string <mac>-rex`.
  A new node signs in through the link in `rex server status`
  (`authenticate:`), opened by Jason as admin@jasonscholtz.net.
  Check with `rex server status` (`tailscale: running · <mac>-rex.tail483f5.ts.net`);
  doctor warns if it doesn't.

  Check with `tailscale serve status` on each machine. Only ghost is ever
  shared, never silence. People ghost is shared with get a grant for one
  app's port only (proofs: `tcp:8443`), never 443, and no other rule may
  match `autogroup:shared` (the default `"src": ["*"]` rule does), or the
  limit means nothing. The policy lives in the Tailscale admin console; the
  proposed change for the box (`tag:grokbot` limited to ghost:443) is
  written up in [tailnet-policy.md](tailnet-policy.md) and is not applied
  until Jason pastes it in.

## Where things live

- **Repo**: `github.com/scozu/environment` (public, deliberately secrets-free).
  Stow package `home` → target `$HOME`:
  ```sh
  cd ~/Developer/environment && stow --no-folding -t "$HOME" home
  ```
- **Shared via Stow**: `.zshenv` (PATH), `.zshrc`, `~/.ssh/config`, Neovim
  baseline, Ghostty, Zed `settings.json`, OpenCode `opencode.jsonc`,
  `agents/lead.md`, and `AGENTS.md`, Claude Code `~/.claude/settings.json` and `~/.claude/rules/pstack-models.md`, and Cursor rules (`~/.cursor/rules/*.mdc`).
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

- **Default agent is `lead`**: pinned to Opus on the Claude subscription
  (`claude-agent/opus`). It scopes tasks, reviews the diff once, and commits. It
  makes edits through subagents, and its shell allows git and read-only commands
  and asks before anything else. That limit prevents accidents; it is not a
  security boundary.
- **Models**: the `general` and `explore` subagents run on
  `opencode-go/claude-haiku-5-5`. The global default (so `build` and `plan`),
  compaction, title, and summary run on `opencode-go/deepseek-v4.1-flash`.
  `/models` still overrides a session's model. Use `opencode-go/`, not
  `opencode/`, which is pay-as-you-go. If Console is signed out, subagents fail
  with `Reconnect OpenCode Console to continue`; fix it with `opencode auth login`.
- **Long threads cost more**: every turn resends the whole history. Run
  `/compact` after finishing a chunk of work, and start a new thread for a
  separate task.
- **Usage**: `claude -p "/usage"` shows Claude plan limits;
  `opencode api get /api/experimental/usage/limits` shows OpenCode Go usage.
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
  `.zshenv` need it), `make` (to build stow), `openssh-client`, `curl` and
  `unzip` (sync-tools downloads and unpacks the tarballs), and whatever provides
  `shasum` (sync-tools checks sha256 with `shasum -a 256`; the apt package name
  is unverified on Linux — find it with `apt-file search /usr/bin/shasum`).
  Everything else follows the playbook: build stow 2.4.1 into `~/.local/opt/stow`, then
  `stow --no-folding -n -v -t "$HOME" home` → move conflicts aside as
  `<file>.pre-stow` → apply, then `scripts/sync-tools.sh`, then
  `scripts/doctor.sh`.
- `~/.ssh/config.local` on the box holds `IgnoreUnknown UseKeychain`: the
  shared `~/.ssh/config` uses the Apple-only `UseKeychain` option, which
  Linux OpenSSH rejects otherwise. `~/.ssh` must be mode 700 (doctor checks it).
- Tailscale: do not install a Tailscale client or tailscaled on the box —
  the box is replaced from time to time, and a local client would be wiped
  with it. Tailnet access comes from Grok Bot's Tailscale connector,
  authenticated in the Grok Bot app (Connect apps → Tailscale). Once
  connected, shell commands on the box reach tailnet hosts by their full
  MagicDNS name (`name.tail483f5.ts.net`) over HTTPS. The connector is
  built for HTTPS (MCP servers on the tailnet, via Tailscale OAuth apps),
  and the box's shell egress is an HTTP proxy: SSH and other raw TCP from
  the box don't work, even though the connector itself can see ghost:22.
  Prefer the full `.ts.net` name. This only works during the owner's own
  turns and routines; disconnecting cuts connections. The connector's tailnet device is
  `grokbot-user-158631703` (`100.121.13.52`); the old `grokbox` device
  (`100.127.67.48`) was the removed local tailscaled and can be deleted
  in the admin console.
- **The box and ghost — ghost-env MCP.** The box works on ghost through
  envd, a small MCP server on ghost (see "envd" below), reached at
  `https://ghost.tail483f5.ts.net/mcp` and added in Grok Bot as an MCP
  server (Streamable HTTP, no auth header: envd identifies the caller
  with `tailscale whois`). Tools: `doctor`, `versions`, `repo_status`,
  `repo_pull` (fast-forward on a clean main only), `stow_dry_run`,
  `sync_tools_check`. That replaces `ssh ghost` for parity checks: doctor
  on the box skips the ssh parity lines and points at the `versions` tool.
  For anything envd doesn't cover, ghost itself (or Jason) runs it.
- HTTP to the other tailnet services (opencode `:4096`, proofs `:8443`)
  goes directly to the MagicDNS name — no SOCKS proxy and no local
  tailscaled — until the `tag:grokbot` lockdown in
  [tailnet-policy.md](tailnet-policy.md) is applied; after that the box
  reaches ghost:443 only. Doctor on the box checks
  `https://ghost.tail483f5.ts.net/healthz` (fails with "connect Tailscale
  in Grok Bot, or start envd on ghost") and warns if
  `https://silence.tail483f5.ts.net:8443` gives no HTTPS response at all
  (silence runs no envd, and the laptop may be asleep; any HTTP status
  counts as reachable). The box's ssh key `~/.ssh/id_ed25519` and the
  `Host silence` entry in its `~/.ssh/config.local` are left in place but
  unused while SSH from the box doesn't work.
- OpenCode on ghost from the box: `opencode run --server https://ghost.tail483f5.ts.net:4096 "<task>"`
  with `OPENCODE_PASSWORD` from `~/.config/opencode/ghost-server.env` (machine-local,
  mode 600). The connector reaches that URL directly, so no local port
  forward or `/etc/hosts` rewrite is needed. Sessions live on ghost's
  server and show up in the desktop and iOS apps.
- OpenCode: CLI only on the box, installed with the v2 installer (see the
  inventory in [tools.md](tools.md)). No service; the Stowed
  `opencode.jsonc` applies. `~/.bashrc` also puts `~/.opencode/bin` on PATH.
- Login shell stays bash; `~/.bashrc` already puts `~/.local/bin` first on
  PATH. The stowed `.zshenv` covers zsh and doctor.
- Pre-existing system copies (`/usr/bin/node`, `/usr/local/bin/{gh,bun,npm}`)
  are left alone; `~/.local/bin` shadows them.
- Rex: no Linux build yet. The stowed `~/.local/bin/rex` shim runs ghost's
  rex over `ssh ghost` (newest `RexServer/Versions/*`), which needs SSH
  from the box, so it does not work there today (doctor prints an info
  line). `REX_SSH_HOST=<host>` targets another Mac. On the Macs the same
  file just execs the local rex.
- Claude Code installs itself (native installer) to
  `~/.local/share/claude/versions/<ver>` with `~/.local/bin/claude` → that
  version. The shared `~/.claude/settings.json` sets `DISABLE_AUTOUPDATER=1`,
  so upgrade by hand with `claude install <version>`. It also turns off the
  claude.ai connector, skill, and plugin syncing. pstack comes from the
  `cursor-plugins` marketplace; its model rule is the stowed
  `~/.claude/rules/pstack-models.md`. Login is interactive and per machine.
  **Do not run `/pstack:setup-pstack` casually**: it overwrites the tracked rule
  file, which is a symlink into this repo. If it runs, check `git diff` and
  `git restore home/.claude/rules/pstack-models.md`.

### envd — the ghost-env MCP server (ghost only)

- What: `home/.local/share/envd/envd.ts`, a single-file bun server with no
  dependencies, started by the stowed `~/.local/bin/envd` shim. MCP
  Streamable HTTP, JSON responses (no SSE), stateless: `POST /mcp`
  (`initialize`, `ping`, `tools/list`, `tools/call`) and `GET /healthz`
  (`ok`, no auth, used by doctor). Listens on `127.0.0.1:8790` only.
- Tools run fixed argv lists in `~/Developer/environment`, one at a time,
  with a 120 s timeout, and take no arguments. No arbitrary commands.
- Auth on `/mcp`: the request must come from loopback with exactly one
  `X-Forwarded-For` address in the tailnet ranges (what `tailscale serve`
  sends), and `tailscale whois` on that address must show one of: an
  untagged node owned by an allowed login (default
  `admin@jasonscholtz.net`), a node with an allowed tag (default
  `tag:grokbot`), or a tagged node whose hostname starts with an allowed
  prefix (default `grokbot-`; tagged only, so a shared-in device can't
  pass by its name). Everything else, including whois failing, gets 403.
  `Tailscale-User-*` headers are not trusted on their own. Overrides go in
  `~/.config/envd/env.local` on ghost (machine-local `KEY=VALUE` lines):
  `ENVD_ALLOW_LOGINS`, `ENVD_ALLOW_TAGS`, `ENVD_ALLOW_HOST_PREFIXES`
  (comma-separated), `ENVD_PORT`, `ENVD_TIMEOUT_S`, `ENVD_TAILSCALE`.
  `ENVD_INSECURE_LOCAL_TEST=1` (process env only) skips auth for local
  testing on Linux and is refused on macOS.
- Run on ghost: LaunchAgent `dev.scozu.envd` (RunAtLoad, KeepAlive), log
  `~/.local/var/envd.log`. The plist template is `launchd/dev.scozu.envd.plist`,
  outside the Stow package on purpose: a stowed plist would also land in
  silence's `~/Library/LaunchAgents` and auto-load there at login.
  `scripts/envd-setup.sh` (ghost only, idempotent) renders it into
  `~/Library/LaunchAgents`, bootstraps or kickstarts it, waits for
  `/healthz`, adds `tailscale serve --bg --https=443 http://127.0.0.1:8790`
  if 443 has no mapping (it refuses if 443 serves something else, and
  never touches 4096 or 8443), then prints `tailscale serve status`.
- Install or update on ghost:
  ```sh
  cd ~/Developer/environment && git pull --ff-only
  stow --no-folding -n -v -t "$HOME" home   # dry run
  stow --no-folding -t "$HOME" home
  scripts/envd-setup.sh
  scripts/doctor.sh
  ```
  After a pull that changes `envd.ts`, re-run `scripts/envd-setup.sh` (it
  restarts the agent). Remove: `launchctl bootout gui/$(id -u)/dev.scozu.envd`,
  delete the plist, `tailscale serve --https=443 off`.
- In Grok Bot: add an MCP server with URL
  `https://ghost.tail483f5.ts.net/mcp` (needs the Tailscale connector).

### 7. Terminal / SSH

- `ssh ghost` — passwordless, fast (multiplexed).
- `ssh silence` works from ghost non-interactively (bare MagicDNS name; no alias
  in `~/.ssh/config`). ghost manages silence over SSH. To update silence, run these from
  ghost: `git pull --ff-only` in `~/Developer/environment`, then Stow
  (`stow --no-folding -t "$HOME" home`), then doctor. Run doctor in a zsh
  interactive shell, because silence sets `OPENCODE_SERVER_PASSWORD` in
  `~/.zshrc.local`, which a plain SSH command does not load:
  `ssh silence 'zsh -ic "cd ~/Developer/environment && scripts/doctor.sh"'`.
- Copy files: `scp`/`rsync` over the alias; tunnels if ever needed:
  `ssh -L 4096:127.0.0.1:4096 ghost`.

## Rules that keep this working

1. Never commit secrets or app state (keys, `service.json`, auth, caches).
2. Machine-specific → `.local` override files (gitignored, auto-sourced).
3. Always Stow dry-run before real runs; review diffs before committing.
4. silence is a client: no local OpenCode service and no tool launchd jobs
   there. The one exception is app LaunchAgents listed under Tailnet ports
   (today the Proofs app).
5. The service password lives in one place: ghost's
   `~/.config/opencode/service.json`.
6. Tools follow the direct-install pattern. Every install or update goes
   through the playbook in [tools.md](tools.md) and updates its inventory in
   the same commit (tarball tools are scripted in `scripts/sync-tools.sh`);
   ghost and silence stay at the same versions, and the box matches them
   except Claude Code (Postgres is ghost-only).
7. Tailnet apps listen on `127.0.0.1` and go through Tailscale Serve on the
   port in Tailnet ports. Never Funnel: it makes a page public.
8. The box reaches ghost over HTTPS only (Grok Bot's Tailscale connector,
   then ghost-env MCP on 443). No SSH from the box, and no tailscale
   client on the box.

## Status checks & maintenance

- OpenCode service: on ghost `opencode service status` (launchd job:
  `ai.opencode.service`).
- Postgres (ghost): start on demand — `pg_ctl -D ~/.local/var/postgres start`
  when working on the local app, `stop` when done. No launchd job by design;
  ghost-only.
- Tailscale proxy: `tailscale serve status`.
- envd (ghost): `launchctl print gui/$(id -u)/dev.scozu.envd`,
  `curl http://127.0.0.1:8790/healthz`, log `~/.local/var/envd.log`.
- SSH server: socket-activated — `ssh ghost 'echo ok'` is the test.
- Updates: opencode self-updates (its launchd job picks up new versions on
  restart), and the GUI apps (Zed, Cursor, Tailscale, ChatGPT) auto-update
  themselves. The tarball tools (nvim, pnpm, bun, node, gh, cloudflared,
  claude, ffmpeg, rustup; the box skips claude and rustup) update via
  `scripts/sync-tools.sh`; stow and Postgres stay manual per
  [tools.md](tools.md) — pin the version and update the inventory there.
  Upstream drift is reported weekly on ghost; the log is
  `~/.local/var/check-upstream.log`, and `scripts/check-upstream.sh` runs it
  on demand.

## Known quirks / parked items

- Zed **OpenCode provider** (API key) path parked — console has no personal
  API keys yet; ACP covers it meanwhile.
- Neovim customization and Herdr: next stage, deliberately not started.
