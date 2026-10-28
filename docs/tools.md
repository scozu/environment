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
   - **Official release tarball or standalone prebuilt binary** — most tools
     (nvim, pnpm, bun, ripgrep, gh, go, …). Relocatable, no build
     dependencies.
   - **Build from source with `--prefix`** — only when no prebuilt binary
     exists (stow and Postgres are the existing examples).
   - **Official installer script** — last resort; only when it installs to a
     known prefix and does not edit shell files (OpenCode is the exception).
2. **Pin the version.** Never install "latest". For the tarball tools the
   authoritative pin lives in `scripts/sync-tools.sh` — edit it there and
   mirror the change in the inventory below in the same commit. Source
   builds and installers pin at install time.
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
6. **Approve unsigned binaries (macOS only).** macOS blocks the first run of unsigned
   binaries ("Apple could not verify … is free of malware"). Run it once
   (blocked), then System Settings → Privacy & Security → "Allow Anyway",
   then run again. Terminal fallback:
   `xattr -d com.apple.quarantine "$HOME/.local/opt/<tool>/bin/<name>"`.
   Neovim's release binary is the known case.
7. **Verify**: `<tool> --version`, then `scripts/doctor.sh` from the repo.
8. **Record**: update the inventory table below (version) in the same commit.
9. **Sync the other machine.** silence exists to stay in sync with ghost, and
   syncs run **from silence** — silence is SSH-client only (Remote Login is
   off), so ghost can never reach it. When silence is awake, run this
   playbook on silence itself, then doctor there: `ssh ghost` works from
   silence, and doctor on silence checks version parity against ghost.
   For the direct release tools the playbook is scripted — on silence run
   `git pull && scripts/sync-tools.sh && scripts/doctor.sh`; the script
   compares installed versions against the pins and downloads only what
   differs. stow and Postgres remain manual playbook steps.
   Run the playbook — never copy `~/.local/opt` wholesale. Data under
   `~/.local/var` is machine-local, never copied. Exception: server tools
   live on one machine only — see Server tools below.
   **The box** (Linux) runs the same playbook on itself:
   `git pull && scripts/sync-tools.sh && scripts/doctor.sh`. sync-tools
   picks the Linux build by `uname -s`/`uname -m` (x86_64 or aarch64); stow
   is source-built the same way. Step 6 does not apply on Linux.

**Remove**: delete the symlinks from `~/.local/bin`, then the directory in
`~/.local/opt`, update the inventory, doctor both machines.

**Roll back**: repoint the symlink at `~/.local/opt/<tool>-<oldver>` and
update the inventory.

## Inventory

The authoritative pins for the tarball tools live in `scripts/sync-tools.sh`;
this table mirrors them and is updated in the same commit.

| Tool | Source | Version | Location | Entry points in `~/.local/bin` | Notes |
|---|---|---|---|---|---|
| stow | source build (GNU tarball) | 2.4.1 | `~/.local/opt/stow` | `stow` | `./configure --prefix=… && make && make install` (same on the box; needs `make` from apt) |
| nvim | release tarball | 0.12.6 | `~/.local/opt/nvim` | `nvim` | macOS build: `nvim-macos-$(uname -m).tar.gz`; box: `nvim-linux-{x86_64,arm64}.tar.gz`. Unsigned → quarantine approval (step 6; the sync script strips quarantine xattrs best-effort). No checksums published. |
| pnpm | release tarball (standalone build) | 12.11.2 | `~/.local/opt/pnpm` | `pnpm` | The standalone build bundles its own Node; box: `pnpm-linux-{x64,arm64}.tar.gz` (glibc, not `-musl`). Pins are bare semver; `tag()` in `sync-tools.sh` adds the upstream tag prefix (`v12.11.2`). Never use the curl installer (writes to `~/Library/pnpm` and edits shell files). Project Node versions come from `pnpm env use` — the global Node on PATH is the tarball below. No checksums published. |
| bun | release tarball (zip) | 1.4.3 | `~/.local/opt/bun` | `bun`, `bunx` | Single binary from `bun-darwin-aarch64.zip` (Apple Silicon) or `bun-darwin-x64.zip` (Intel) — bun's macOS arm64 asset is named `aarch64`, not `arm64`. Box: `bun-linux-x64.zip` / `bun-linux-aarch64.zip` (not `-baseline`/`-musl`). Checksums in `SHASUMS256.txt`. `bunx` is a symlink to `bun`. Global installs land in `~/.bun/bin` — not on PATH by default. |
| node | release tarball | 24.21.0 (LTS) | `~/.local/opt/node` | `node`, `npm`, `npx` | Official `node-v24.21.0-darwin-$(uname -m).tar.gz` (box: `node-v24.21.0-linux-{x64,arm64}.tar.gz`); checksums in `SHASUMS256.txt`. Global Node; project Node comes from `pnpm env use`. `corepack` intentionally not linked (deprecated). |
| gh | release tarball (zip) | 2.102.0 | `~/.local/opt/gh` | `gh` | Official `gh_2.102.0_macOS_arm64.zip` (box: `gh_2.102.0_linux_{amd64,arm64}.tar.gz`); checksums in `gh_2.102.0_checksums.txt`. Single binary + man pages. |
| cloudflared | release binary (macOS: tgz) | 2026.10.5 | `~/.local/opt/cloudflared` | `cloudflared` | Official `cloudflared-darwin-arm64.tgz` (Intel `darwin-amd64`; box: raw `cloudflared-linux-{amd64,arm64}`), installed as `opt/cloudflared/bin/cloudflared`. No checksums file: the sha256 per asset is pinned in `pinsum()` in `sync-tools.sh` (GitHub asset digests; the release-notes sums for the darwin tgz don't match the uploaded files). Runs the proofing tunnel on ghost; the tunnel token is machine-local, never in the repo. |
| claude | official standalone binary | 2.1.303 | `~/.local/opt/claude` | `claude` | Claude Code: `downloads.claude.ai/claude-code-releases/<version>/darwin-<arch>/claude`. SHA-256 from `manifest.json`; macOS signature verified against Anthropic's team `Q6L2SF6YDW`. Stowed `~/.claude/settings.json` sets `DISABLE_UPDATES=1`; upgrades use `sync-tools.sh`, not `claude update` or `claude install`. Credentials and sessions stay machine-local. Run `claude` to sign in. Macs only; the box uses the native installer (row below) and `sync-tools.sh` skips claude on Linux. |
| opencode | official installer | v2.1.4 | `~/.opencode/bin` | `opencode` | Exception to the opt/ pattern; self-updates. ghost runs it as a service (launchd `ai.opencode.service`). OpenCode 2 uses the v2 installer: `curl -fsSL https://opencode.ai/v2/install \| bash -s -- --version 2.1.4 --no-modify-path` (the plain `/install` script refuses 2.x; `--no-modify-path` because `.zshenv` already has `~/.opencode/bin`). It pulls `@opencode/cli-<os>-<arch>` from npm. Same on the box (`linux-x64`); no service there — CLI only. |
| tailscale (box) | official apt repo (`pkgs.tailscale.com/stable/debian trixie`) | 1.104.1 | `/usr/bin/tailscale`, `/usr/sbin/tailscaled` | — | Box only; the Macs use the Tailscale GUI app. System package by necessity (tailscaled runs as root), so it is an exception to the opt/ pattern like the apt bootstrap packages; updates via `apt`. No systemd on the box, so `~/.local/bin/box-tailscaled` (machine-local) starts tailscaled in kernel-TUN mode (`TS_USERSPACE=1` for userspace networking) with a SOCKS5/HTTP proxy on `localhost:1055`. |
| claude (box) | official native installer | 2.1.302 | `~/.local/share/claude/versions/<ver>` | `claude` | Box only. Exception to the opt/ pattern like opencode: the installer manages its own prefix and the `~/.local/bin/claude` link. The shared settings set `DISABLE_UPDATES=1`, so upgrade the box deliberately with `claude install <version>`. Plugin: `pstack@cursor-plugins` 0.15.32 (marketplace `cursor-plugins`). Login is per machine, never copied. |
| rex (shim) | repo script, stowed | — | `home/.local/bin/rex` (in this repo) | `rex` | Not an install: a wrapper for the Rex (superlogical) CLI, stowed on all three machines. macOS: never shadows a real rex — execs the first other `rex` on PATH (Rex terminals add one), else the newest numeric `~/Library/Application Support/com.superlogical.rex/RexServer/Versions/*/Rex Server.app/Contents/MacOS/rex`; errors if neither exists. Linux (box): Rex has no Linux build yet, so it runs ghost's newest rex over `ssh ghost` (`REX_SSH_HOST` overrides), args `%q`-quoted, exit code preserved, `ssh -t` only when stdin/stdout are a tty. Rex itself is the GUI app `Rex Beta.app` on the Macs (GUI apps table). |
| postgres | source build | 16.15 | `~/.local/opt/postgres` | `postgres`, `psql`, `pg_ctl`, `initdb`, `pg_isready` | Built `--without-icu`. The only server tool — see below. Minor updates rebuild in place (no dump, no `pg_upgrade`, but the configure `--prefix` must be the final path). 16.15 fixes many CVEs; note the new `output_plugin_libraries` whitelist if logical decoding is ever used. |

## GUI apps — the /Applications exception

Desktop apps are macOS `.app` bundles, not CLI programs, so they install to
`/Applications` instead of `~/.local/opt`. Spotlight, Launchpad, login items,
and the apps' own updaters all expect that location, and no symlinks are
needed. The playbook still applies, with these substitutions:

1. **Source**: the vendor's direct download. No Homebrew, no mirrors. Pin the
   version and its SHA-256 from the vendor's release feed or Homebrew's cask
   for that app (used as a pin record only, never installed through brew).
2. **Verify** before installing. Check the zip's SHA-256 against the pin, then
   on the unpacked bundle: `codesign --verify --deep --strict` and
   `spctl -a -vv -t exec` must show `Notarized Developer ID` from the vendor's
   team.
3. **Install** with `ditto` (it keeps signatures intact), never `cp`:
   `ditto ChatGPT.app /Applications/ChatGPT.app`.
4. **Record** the version in the table below, in the same commit.
5. **No pinned rollback.** These apps self-update, like Zed, Cursor, and
   Tailscale. The version column records what was installed, not what is
   enforced. Sign-in state lives under `~/Library` and is never copied between
   machines.
6. Repeat on silence. Doctor does not check GUI apps.

| App | Source | Version | Location | Updates | Notes |
|---|---|---|---|---|---|
| ChatGPT | `ChatGPT-darwin-arm64-<ver>.zip` from `persistent.oaistatic.com/codex-app-prod/` (feed: `appcast.xml`) | 26.1007.30912 (build 20156) | `/Applications/ChatGPT.app` | Sparkle, self-updating | Bundle id `com.openai.codex`. Intel uses `ChatGPT-darwin-x64-<ver>.zip`. Verified: SHA-256 `b699a8c2…f815a3` (matches the Homebrew cask pin); signed `Developer ID Application: OpenAI OpCo, LLC (2DC432GLL2)`, notarized and stapled. The app is named ChatGPT; the older app is "ChatGPT Classic". |
| Rex Beta | `Rex.dmg` from the Rex beta (Superlogical; Sparkle feed `blob.superlogical.com/public/rex-app/preview/appcast.xml`) | 0.1.0 (build 1541) on silence; ghost 0.1.0 (build 1497) | `/Applications/Rex Beta.app` | Sparkle, self-updating | Bundle id `com.superlogical.rex`. Verified on silence: dmg SHA-256 `b2e6583d…07c3f3`; signed `Developer ID Application: Superlogical, Inc. (AG92C3PT77)`, notarized. The app bundles its own server and `rex` CLI under `~/Library/Application Support/com.superlogical.rex/RexServer/Versions/<build>/` (the stowed shim finds it). Config: stowed `~/.config/rex/init.lua`. ghost runs built-in Tailscale as node `rex` (pref `rex.server.tailnet-hostname`, see workflows.md); silence keeps built-in Tailscale off. Install from the dmg with `ditto`; the dmg in Downloads is left in place. |

## Retention and upstream checks

The lifecycle of a pinned tool has four steps, each with one owner:

1. **Detect (automatic, read-only).** `scripts/check-upstream.sh` compares
   each pin against upstream and reports `current` or `behind`. It installs
   nothing. On ghost, launchd job `dev.scozu.check-upstream` runs it every
   Monday at 09:00; the log is `~/.local/var/check-upstream.log`. The plist
   lives in `~/Library/LaunchAgents` on ghost only, like the OpenCode plist —
   it is machine-local, not in the repo. Doctor on ghost checks that the job
   is loaded. Silence has no tool launchd jobs (rule 4); its parity is checked
   by doctor.
2. **Propose (manual, reviewed).** A `behind` line becomes a commit that
   changes the pin in `sync-tools.sh` and the inventory row here.
3. **Apply.** `scripts/sync-tools.sh` on each machine, when it is awake.
4. **Retain.** After a verified install, `sync-tools.sh` prunes every older
   `~/.local/opt/<tool>-*` and keeps exactly one rollback copy (the version it
   just replaced). The rollback copy is removed by the next upgrade. Nothing
   is pruned unless the new version verified first.

Stow and Postgres are outside this loop by design. Postgres's data directory
is tied to its build, so its old installs are removed by hand, once the
upgrade is verified.

Auto-applying pinned CLIs is deliberately not done. nvim and pnpm publish no
checksums, so TLS to GitHub is their only integrity check, and silence sleeps,
so unattended bumps would drift the two machines. Self-updating apps (OpenCode,
ChatGPT, Zed, Cursor, Tailscale) keep their own update channels.

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
- Upgrade (minor/patch): a minor bump keeps the on-disk format, so no dump and
  no `pg_upgrade` — but the `--prefix` must be the **final** path
  (`~/.local/opt/postgres`) at configure time, or the Mach-O binaries embed the
  staging path in their `libpq` install name and clients fail with
  "Library not loaded". Sequence:
  1. Download `postgresql-<v>.tar.bz2` and its `.sha256` from
     `ftp.postgresql.org/pub/source/v<v>/`; verify.
  2. Extract to a scratch tree; `./configure --prefix="$HOME/.local/opt/postgres"
     --without-icu`; `make -j8 && make install` (it overwrites in place —
     never configure a temporary `opt/postgres.new` prefix).
  3. `pg_ctl -D ~/.local/var/postgres -m fast stop`, back up the data dir
     (`cp -a`), start again, run `psql … "select version();"` to confirm.
  4. Update the inventory row above.
  A major version change needs `pg_upgrade`, not a rebuild — do that
  deliberately.

## Adding a new tool — worked example

"Install bun" would go like this. Bun ships as an official release tarball
with prebuilt binaries (preferred source), so:

1. Pin: pick the exact version from the releases page.
2. Download the macOS zip — mind bun's naming: `bun-darwin-aarch64.zip` on
   Apple Silicon (not `arm64`), `bun-darwin-x64.zip` on Intel — and verify
   the checksum.
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
