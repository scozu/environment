# environment — dotfiles and tools for ghost and silence

One repo that defines both Macs: **ghost** (Mac Studio, the always-on compute
machine) and **silence** (MacBook Pro, the portable client). Config is shared
through Stow. Programs are installed directly — no Homebrew. Each machine
keeps its own secrets and app state.

## The machines

- **ghost** — always on. Owns all projects, the OpenCode service, Postgres,
  the SSH host, and the Zed/Cursor remote servers. Work happens here.
- **silence** — portable client. UIs run here; files, tools, and agents act
  on ghost over Tailscale + SSH. silence is set up; its ongoing job is to
  stay in sync with ghost.

## What this repo contains

- `home/` — the Stow package (dotfiles), target `$HOME`
- `scripts/doctor.sh` — read-only health check for the current machine
- `docs/tools.md` — how programs are installed and updated (read this before
  touching any tool)
- `docs/workflows.md` — the daily operating manual

## How programs are installed (no Homebrew)

Every CLI tool lives at `~/.local/opt/<tool>/` with symlinks to its
executables in `~/.local/bin`, which `.zshenv` puts first on `PATH`. Runtime
state (Postgres data, logs) lives in `~/.local/var/`. One exception: OpenCode
installs itself to `~/.opencode/bin`.

To install or update **any** program — "install bun", "update nvim", anything
— follow the playbook in [docs/tools.md](docs/tools.md). It is the same
procedure for every tool. This README and that file together are the
source of truth: when you change a tool, update its entry in the inventory
in the same commit.

## The three loops

### 1. Stow loop — edit shared config

```sh
cd ~/Developer/environment
stow --no-folding -n -t "$HOME" home   # dry run — read it
stow --no-folding -t "$HOME" home      # apply
```

`--no-folding` links files but leaves parent directories real (`~/.cursor`
and the Cursor `User` directory must stay real; the apps write state into
them).

- Edit files under `home/` in this repo. A GUI may rewrite a linked file
  (Zed settings, Cursor settings, OpenCode config): commit real setting
  changes, `git restore` the noise.
- Stowed files: `.zshenv` (PATH), `.zshrc`, `.ssh/config`, Neovim config,
  Ghostty config, Zed settings, OpenCode `opencode.jsonc`, Cursor rules and
  `User/settings.json`.
- Machine-specific values go in the gitignored `.local` files, which the
  stowed configs source automatically: `~/.zshrc.local` (aliases),
  `~/.zshenv.local` (env vars), `~/.ssh/config.local` (SSH overrides).
- On the other machine: `git pull` — existing symlinks update in place, no
  re-stow needed. On a machine without the links yet, run Stow after pulling.
- If the dry run reports a conflict, move that file out of `$HOME` and retry.

### 2. Tool loop — install or update a program

Pin a version, put the program in `~/.local/opt/<tool>`, symlink its entry
points into `~/.local/bin`, record the version in the tools inventory,
verify with `doctor.sh`, repeat on the other machine. Full procedure:
[docs/tools.md](docs/tools.md).

### 3. Doctor — verify the machine

```sh
cd ~/Developer/environment && scripts/doctor.sh
```

A clean run means the Stow tree is settled and this machine's checks passed.
Run it after every change, and on both machines.

## Never commit these

`.gitignore` blocks the copies that would land inside `home/`:

- SSH private keys, `known_hosts`, `authorized_keys`
- the `.local` override files
- OpenCode `service.json`, `auth.json`, and `~/.local/share/opencode` data
- Cursor `argv.json` (per-machine crash-reporter id), `cli-config.json`,
  plugins, extensions, project caches, and other app state the apps rewrite

## Rules that keep this working

1. No Homebrew. Every tool follows the direct-install pattern, or documents
   its exception in `docs/tools.md`.
2. Docs are part of the system. Any tool change updates the inventory in
   `docs/tools.md` in the same commit.
3. Secrets and app state never enter the repo. Machine-specific config goes
   in the `.local` files.
4. ghost and silence run the same tool versions. Doctor runs clean on both.

## Read the longer docs

- [Tools — install, update, inventory](docs/tools.md)
- [Two-Mac workflow — operating manual](docs/workflows.md)
