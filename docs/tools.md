# Tools — how programs are installed, updated, and removed

No Homebrew. Every CLI program follows one pattern, so "install X" is always
the same procedure. This file is the source of truth for what is installed
and at what version. Keep it current whenever you touch a tool — update the
inventory in the same commit as any install, upgrade, or removal.

## Layout

| Path | Purpose |
|---|---|
| `~/.local/opt/<tool>/` | one directory per program: an extracted release tarball or a source-build prefix |
| `~/.local/bin/` | symlink farm: one link per executable → `~/.local/opt/<tool>/bin/<name>` |
| `~/.local/var/` | runtime state (Postgres data and logs) — never in the repo, never copied between machines |
| `~/.opencode/bin/` | OpenCode's own install prefix (exception — its installer manages it) |

`PATH` is set once, in the stowed `.zshenv`:
`~/.local/bin` first, then `~/.opencode/bin`, then the system default.
Tools never edit shell files to add themselves to PATH. On a machine where
Stow has not been applied yet, export that PATH in the session first or
newly installed commands will be invisible.

## The playbook (install = update)

The same steps install a new tool and upgrade an existing one. Skip nothing.

1. **Choose the source**, in this order of preference:
   - **Official release tarball with prebuilt binaries** — most tools
     (nvim, pnpm, bun, ripgrep, gh, go, …). Relocatable, no build
     dependencies.
   - **Build from source with `--prefix`** — only when no prebuilt binary
     exists (stow and Postgres are the existing examples).
   - **Official installer script** — last resort; only when it installs to a
     known prefix and does not edit shell files (OpenCode is the exception).
2. **Pin the version.** Never install "latest". Write the exact version into
   the command and record it in the inventory below in the same commit.
3. **Download and verify.** When the project publishes checksums (GitHub
   releases publish sha256 files), verify before extracting.
4. **Install into `~/.local/opt`**:
   - tarball: extract, then move the release directory to
     `~/.local/opt/<tool>`. When upgrading, keep the old version as
     `~/.local/opt/<tool>-<oldver>` (or keep the tarball) so rollback is a
     symlink repoint.
   - source: `./configure --prefix="$HOME/.local/opt/<tool>" && make -j && make install`.
5. **Symlink entry points** — one link per executable you want on PATH:
   `ln -sf "$HOME/.local/opt/<tool>/bin/<name>" "$HOME/.local/bin/<name>"`.
6. **Approve unsigned binaries.** macOS blocks the first run of unsigned
   binaries ("Apple could not verify … is free of malware"). Run it once
   (blocked), then System Settings → Privacy & Security → "Allow Anyway",
   then run again. Terminal fallback:
   `xattr -d com.apple.quarantine "$HOME/.local/opt/<tool>/bin/<name>"`.
   Neovim's release binary is the known case.
7. **Verify**: `<tool> --version`, then `scripts/doctor.sh` from the repo.
8. **Record**: update the inventory table below (version) in the same commit.
9. **Sync the other machine.** silence exists to stay in sync with ghost:
   run this playbook on silence too (`ssh silence`, from a session there),
   then doctor there. Run the playbook — never copy `~/.local/opt` wholesale.
   Data under `~/.local/var` is machine-local, never copied. Exception:
   server tools live on one machine only — see Server tools below.

**Remove**: delete the symlinks from `~/.local/bin`, then the directory in
`~/.local/opt`, update the inventory, doctor both machines.

**Roll back**: repoint the symlink at `~/.local/opt/<tool>-<oldver>` and
update the inventory.

## Inventory

| Tool | Source | Version | Location | Entry points in `~/.local/bin` | Notes |
|---|---|---|---|---|---|
| stow | source build (GNU tarball) | 2.4.1 | `~/.local/opt/stow` | `stow` | `./configure --prefix=… && make && make install` |
| nvim | release tarball | 0.12.5 | `~/.local/opt/nvim` | `nvim` | macOS build: `nvim-macos-$(uname -m).tar.gz`. Unsigned → quarantine approval (step 6). Currently installed as "latest" — pin the version at the next update. |
| pnpm | release tarball (standalone build) | 12.10.1 | `~/.local/opt/pnpm` | `pnpm` | The standalone build bundles its own Node — no system Node exists on these machines. Never use the curl installer (writes to `~/Library/pnpm` and edits shell files). Project Node versions come from `pnpm env use`. |
| bun | release tarball (zip) | 1.4.3 | `~/.local/opt/bun` | `bun`, `bunx` | Single binary from `bun-darwin-$(uname -m).zip`; checksums in `SHASUMS256.txt`. `bunx` is a symlink to `bun`. Global installs land in `~/.bun/bin` — not on PATH by default. |
| opencode | official installer | v2.0.26 | `~/.opencode/bin` | `opencode` | Exception to the opt/ pattern; self-updates. ghost runs it as a service (launchd `ai.opencode.service`). |
| postgres | source build | 16.10 | `~/.local/opt/postgres` | `postgres`, `psql`, `pg_ctl`, `initdb`, `pg_isready` | Built `--without-icu`. The only server tool — see below. |

## Server tools

A program with a persistent data directory (today: Postgres) follows the
same playbook, plus three rules that follow from being a server:

1. **It lives on one machine** — the one where its data lives. No second
   install on the other machine, and its data dir is never copied between
   machines.
2. **Decide on-demand vs always-on.** A server that serves one local app is
   started on demand (`pg_ctl … start` when needed, `stop` when done). A
   server that should survive reboots gets a launchd job instead, mirroring
   `ai.opencode.service.plist`.
3. **Doctor checks binaries and versions, never "is it running"** — a
   stopped server is a valid state.

Any future server tool (redis, etc.) gets these same rules, so the
exceptions below are the rules, not special cases.

## Postgres notes

Postgres is the only server tool. Data: `~/.local/var/postgres`, log:
`~/.local/var/postgres.log`, listening on `127.0.0.1:5432` on ghost. Built
`--without-icu`.

- **On-demand, by choice**: it serves one local app on ghost, so no launchd
  job and no connection to the OpenCode service. Start when working on the
  app, stop when done:
  `pg_ctl -D ~/.local/var/postgres start|stop|status`.
- Back up with `pg_dump` if it matters.
- Upgrade: a new minor/patch is the same playbook (rebuild into
  `~/.local/opt/postgres`, `pg_ctl restart` against the existing data dir).
  A major version change needs `pg_upgrade`, not a rebuild — do that
  deliberately.

## Adding a new tool — worked example

"Install bun" would go like this. Bun ships as an official release tarball
with prebuilt binaries (preferred source), so:

1. Pin: pick the exact version from the releases page.
2. Download `bun-darwin-$(uname -m).zip` (or `.tar.gz`), verify the checksum.
3. Extract and move to `~/.local/opt/bun` (keep the old version dir when
   upgrading).
4. Symlink: `ln -sf "$HOME/.local/opt/bun/bun" "$HOME/.local/bin/bun"` — plus
   one link per additional executable it ships (`bunx`).
5. Approve first run if Gatekeeper blocks it (step 6).
6. `bun --version`, `scripts/doctor.sh`, update the inventory table above.
7. Repeat on silence; doctor there.

Every tool that ships a prebuilt tarball is exactly this procedure. A tool
that must be built from source swaps step 4 for the configure/make variant;
the rest is identical.
