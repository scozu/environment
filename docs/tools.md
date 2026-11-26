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
| `~/.opencode/bin/` | standalone OpenCode CLI: the Linux box's install and the Mac fallback (exception — its installer manages it) |

`PATH` is set once, in the stowed `.zshenv`:
`~/.local/bin` first, then `~/.opencode/bin`, then the system default.
The same file exports `RUSTUP_HOME` and `CARGO_HOME` to
`~/.local/opt/rustup/{rustup,cargo}`, so the rustup proxies in `~/.local/bin`
(and Claude Code, when started from a zsh) see them. Tools never edit shell
files to add themselves to PATH. On a machine where Stow has not been applied
yet, export that PATH (and the rustup homes) in the session first or newly
installed commands will be invisible.

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
   ghost runs the sync over SSH (`ssh silence` works non-interactively; see
   [workflows.md](workflows.md)). When silence is awake, run this playbook on
   silence from ghost, then doctor there: doctor on silence checks version
   parity against ghost.
   For the direct release tools the playbook is scripted — from ghost run
   `ssh silence 'zsh -ic "cd ~/Developer/environment && git pull --ff-only && scripts/sync-tools.sh && scripts/doctor.sh"'`; the script
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
| nvim | release tarball | 0.12.6 | `~/.local/opt/nvim` | `nvim` | macOS build: `nvim-macos-$(uname -m).tar.gz`; box: `nvim-linux-{x86_64,arm64}.tar.gz`. Unsigned → quarantine approval (step 6; the sync script strips quarantine xattrs best-effort). No checksums published upstream; the sha256 per asset (macOS arm64, Linux x86_64 and arm64) is pinned in `pinsum()`, from the download and checked against the GitHub asset digest. |
| pnpm | release tarball (standalone build) | 12.23.0 | `~/.local/opt/pnpm` | `pnpm` | The standalone build bundles its own Node; box: `pnpm-linux-{x64,arm64}.tar.gz` (glibc, not `-musl`). Pins are bare semver; `tag()` in `sync-tools.sh` adds the upstream tag prefix (`v12.23.0`). Never use the curl installer (writes to `~/Library/pnpm` and edits shell files). Project Node versions come from `pnpm env use` — the global Node on PATH is the tarball below. No checksums published upstream; the sha256 per asset (macOS arm64, Linux x64 and arm64) is pinned in `pinsum()`, checked against the GitHub asset digest. |
| bun | release tarball (zip) | 1.4.5 | `~/.local/opt/bun` | `bun`, `bunx` | Single binary from `bun-darwin-aarch64.zip` (Apple Silicon) or `bun-darwin-x64.zip` (Intel) — bun's macOS arm64 asset is named `aarch64`, not `arm64`. Box: `bun-linux-x64.zip` / `bun-linux-aarch64.zip` (not `-baseline`/`-musl`). Checksums in `SHASUMS256.txt`. `bunx` is a symlink to `bun`. Global installs land in `~/.bun/bin` — not on PATH by default. |
| node | release tarball | 24.22.3 (LTS) | `~/.local/opt/node` | `node`, `npm`, `npx` | Official `node-v24.22.3-darwin-$(uname -m).tar.gz` (box: `node-v24.22.3-linux-{x64,arm64}.tar.gz`); checksums in `SHASUMS256.txt`. Global Node; project Node comes from `pnpm env use`. `corepack` intentionally not linked (deprecated). |
| gh | release tarball (zip) | 2.106.0 | `~/.local/opt/gh` | `gh` | Official `gh_2.106.0_macOS_arm64.zip` (box: `gh_2.106.0_linux_{amd64,arm64}.tar.gz`); checksums in `gh_2.106.0_checksums.txt`. Single binary + man pages. |
| cloudflared | release binary (macOS: tgz) | 2026.11.2 | `~/.local/opt/cloudflared` | `cloudflared` | Official `cloudflared-darwin-arm64.tgz` (Intel `darwin-amd64`; box: raw `cloudflared-linux-{amd64,arm64}`), installed as `opt/cloudflared/bin/cloudflared`. No checksums file: the sha256 per asset is pinned in `pinsum()` in `sync-tools.sh` (GitHub asset digests; the release-notes sums for the darwin tgz don't match the uploaded files). Runs the proofing tunnel on ghost; the tunnel token is machine-local, never in the repo. |
| claude | official standalone binary | 2.1.332 | `~/.local/opt/claude` | `claude` | Claude Code: `downloads.claude.ai/claude-code-releases/<version>/darwin-<arch>/claude`. SHA-256 from `manifest.json`; macOS signature verified against Anthropic's team `Q6L2SF6YDW`. Stowed `~/.claude/settings.json` sets `DISABLE_AUTOUPDATER=1`; upgrades use `sync-tools.sh` (a manual `claude install <version>` also works), not `claude update`. Credentials and sessions stay machine-local. Run `claude` to sign in. Macs only; the box uses the native installer (row below) and `sync-tools.sh` skips claude on Linux. |
| ffmpeg | static build (Martin Riedl's build server, `ffmpeg.martin-riedl.de`) | 9.1 | `~/.local/opt/ffmpeg` | `ffmpeg`, `ffprobe` | FFmpeg itself publishes source only, so this is the prebuilt static release from the build server: `download/<platform>/<build>_9.1/{ffmpeg,ffprobe}.zip`, one binary per zip, installed as `opt/ffmpeg/bin/`. Platform branches in `sync-tools.sh`: macOS arm64 (`macos/arm64`, build 1795207104) and Linux (`linux/amd64` 1795205506, `linux/arm64` 1795204341); Intel macOS is not pinned and sync-tools stops there. The build ids (`ffbuild()`) and each zip's sha256 (`pinsum()`, from the server's `<zip>.sha256`, cross-checked by downloading) are bumped with the pin. macOS binaries are signed by team `KU3N25YGLU` (Martin Riedl), which sync-tools checks; they link only system frameworks. ffplay is not installed. Used by the proofs repo's `bench/verify-library-placement.mjs`. Upstream check: the server's `redirect/latest/linux/amd64/release` redirect. |
| rustup | official rustup-init binary | 1.29.3 | `~/.local/opt/rustup` | `rustup`, `cargo`, `rustc`, `rustfmt`, `cargo-clippy`, `clippy-driver` | Pinned rustup-init from `static.rust-lang.org/rustup/archive/1.29.3/<triple>/rustup-init`, verified against the published `.sha256`. Triples: `aarch64-apple-darwin` (ghost, silence); `x86_64-unknown-linux-gnu` and `aarch64-unknown-linux-gnu` are in the script so the box can opt in later, but `sync-tools.sh` skips rustup on Linux (the box has a system rustc that must not be shadowed). Install: run rustup-init with `RUSTUP_HOME=~/.local/opt/rustup/rustup` and `CARGO_HOME=~/.local/opt/rustup/cargo`, flags `--no-modify-path -y --default-toolchain none` (no curl\|sh, no Homebrew). In-place only — never move `opt/rustup` aside, it holds downloaded toolchains. No default toolchain is installed by the pin; a project (`rust-toolchain.toml`) makes rustup fetch its channel (and rustfmt/clippy) on first `cargo` use. Auto-self-update is disabled so `--check` stays meaningful; bumps go through the pin. The stowed `.zshenv` exports the two homes. Proxies are linked from `opt/rustup/cargo/bin`. Upstream check: `static.rust-lang.org/rustup/release-stable.toml`. |
| cmake | official release tarball | 4.5.1 | `~/.local/opt/cmake` | `cmake` | Official Kitware `cmake-4.5.1-macos-universal.tar.gz`; checksums in `cmake-4.5.1-SHA-256.txt`. The bundle is `opt/cmake/CMake.app`; only `cmake` is linked (not ccmake/cpack/ctest). **Build-only** dependency of the poppler source build — not needed to *run* `pdftotext`. macOS only; `sync-tools.sh` skips cmake on Linux. Upstream check: GitHub `Kitware/CMake` latest release. |
| poppler | source build (official tarball) | 26.11.0 | `~/.local/opt/poppler` | `pdftotext` | There is no official macOS binary. A minimal source build is cleaner than conda-forge (whose runtime closure is large and not a single relocatable prefix). Official `poppler-26.11.0.tar.xz` from `poppler.freedesktop.org` (sha256 pinned in `pinsum()`; upstream publishes a GPG `.sig`, not a sha256 file), built with the pinned cmake above. CMake flags disable Qt, glib, cairo, NSS, gpgme, libcurl, boost, libjpeg, openjpeg, lcms, libtiff, brotli, the C++ frontend, and tests (`CMAKE_DISABLE_FIND_PACKAGE_{Cairo,PNG}`; a stub `pkg-config` satisfies poppler's unconditional `pkg_check_modules(POPPLER_DATA)` without adding a pkg-config pin); `FONT_CONFIGURATION=generic` drops fontconfig and harfbuzz. The one hard library requirement is FreeType (≥ 2.13): a private static build of official freetype 2.15.0 (savannah tarball, sha256 in `pinsum()`, `FT_DISABLE_*` for harfbuzz/png/bzip2/brotli, system zlib) is linked in and not installed to `~/.local/bin`. `BUILD_SHARED_LIBS=OFF` so `pdftotext` links only that static lib plus macOS `libz`/`libc++`/`libSystem`. Other utils may land in `opt/poppler/bin` but only `pdftotext` is linked. macOS only — the box already has apt `poppler-utils` 25.03.0; doctor checks `pdftotext` from `~/.local/bin` on Darwin and skips on Linux. Used by the shadowbox test `sheet_pdf::tests::pdf_text_is_the_exact_labels`. Upstream check: the current `poppler-*.tar.xz` on the Poppler homepage. |
| uv | release tarball | 0.13.10 | `~/.local/opt/uv` | `uv`, `uvx` | Official `uv-aarch64-apple-darwin.tar.gz` (Intel `uv-x86_64-apple-darwin.tar.gz`; box: `uv-{x86_64,aarch64}-unknown-linux-gnu.tar.gz`, glibc not `-musl`). Each tarball holds one top-level `uv-<triple>/` directory with `uv` and `uvx`; sync-tools moves it to `opt/uv`. Checksums in each asset's `<asset>.sha256` file (`sums()`). Upstream tags have no `v` prefix. Upstream check: GitHub `astral-sh/uv` latest release. |
| opencode (Macs) | OpenCode desktop app (self-updating; bundles its CLI) | the app's version (2.4.1 on ghost and silence) | `~/Library/Application Support/ai.opencode.desktop/cli/<ver>-arm64/` | `opencode` (`~/.local/bin/opencode`, the wrapper) | Not an install: `home/.local/bin/opencode` (in this repo) runs the highest `opencode-cli` in the app's cli directory, so the command matches the app. The app runs the shared server from that same CLI (`opencode-cli serve --service`, `127.0.0.1:4096`), and it restarts the server on update: ghost's server is 2.4.1 and started in the same minute the 2.4.1 CLI was installed (2026-11-23 11:40). If no app CLI exists the wrapper falls back to `~/.opencode/bin/opencode`, and exits 127 if neither is there. Doctor checks that `opencode --version` equals the version of the process serving `:4096`. The standalone `~/.opencode/bin` CLI is not used on the Macs. |
| opencode (box, fallback) | official installer | v2.2.5 | `~/.opencode/bin` | `opencode` (via the wrapper, which uses it when no app CLI exists) | The standalone CLI: the box's only install, and the Mac fallback. Nothing updates it; upgrade by re-running the v2 installer with a new version. OpenCode 2 uses the v2 installer: `curl -fsSL https://opencode.ai/v2/install \| bash -s -- --version 2.2.5 --no-modify-path` (the plain `/install` script refuses 2.x; `--no-modify-path` because `.zshenv` already has `~/.opencode/bin`). It pulls `@opencode/cli-<os>-<arch>` from npm. Claude subscription works through the built-in Claude agent (uses that machine's own `claude` login; added in 2.2). The box (`linux-x64`) has no service — CLI only. The launchd job `ai.opencode.service` (ghost) runs this standalone binary, is loaded but idle, and is not used: the app's server holds `:4096`. Remove it (`launchctl bootout` and delete its plist from `~/Library/LaunchAgents`) when convenient. |
| claude (box) | official native installer | 2.1.302 (not yet upgraded; the Macs are on 2.1.325) | `~/.local/share/claude/versions/<ver>` | `claude` | Box only. Exception to the opt/ pattern like opencode: the installer manages its own prefix and the `~/.local/bin/claude` link. The shared settings set `DISABLE_AUTOUPDATER=1`, so upgrade the box deliberately with `claude install <version>`. The pin is recorded here, not enforced by `sync-tools.sh`, which skips claude on Linux. Plugin: `pstack@cursor-plugins` 0.15.32 (marketplace `cursor-plugins`). Login is per machine, never copied. |
| rex (shim) | repo script, stowed | — | `home/.local/bin/rex` (in this repo) | `rex` | Not an install: a wrapper for the Rex (superlogical) CLI, stowed on all three machines. macOS: never shadows a real rex — execs the first other `rex` on PATH (Rex terminals add one), else the newest numeric `~/Library/Application Support/com.superlogical.rex/RexServer/Versions/*/Rex Server.app/Contents/MacOS/rex`; errors if neither exists. Linux (box): Rex has no Linux build yet, so it runs ghost's newest rex over `ssh ghost` (which the box can't do today: no SSH from the box, see workflows.md) (`REX_SSH_HOST` overrides), args `%q`-quoted, exit code preserved, `ssh -t` only when stdin/stdout are a tty. Rex itself is the GUI app `Rex Beta.app` on the Macs (GUI apps table). |
| envd (ghost-env MCP) | repo script, stowed | 1.0.0 | `home/.local/share/envd/envd.ts` + `home/.local/bin/envd` shim (in this repo) | `envd` | Not an install and not a pinned tool: a single-file bun (TypeScript) MCP server with no npm dependencies, run by the pinned bun above. Stowed on all three machines but only runs on ghost, as LaunchAgent `dev.scozu.envd` (template `launchd/dev.scozu.envd.plist`, installed by `scripts/envd-setup.sh`, never stowed). Listens on `127.0.0.1:8790`; tailnet-only `tailscale serve` on 443 fronts it at `https://ghost.tail483f5.ts.net/mcp`. Log `~/.local/var/envd.log`, config `~/.config/envd/env.local` (machine-local). Details in [workflows.md](workflows.md) ("envd"). |
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
| Rex Beta | `Rex.dmg` from the Rex beta (Superlogical; Sparkle feed `blob.superlogical.com/public/rex-app/preview/appcast.xml`) | 0.1.0 (build 1541) on silence; ghost 0.1.0 (build 1497) | `/Applications/Rex Beta.app` | Sparkle, self-updating | Bundle id `com.superlogical.rex`. Verified on silence: dmg SHA-256 `b2e6583d…07c3f3`; signed `Developer ID Application: Superlogical, Inc. (AG92C3PT77)`, notarized. The app bundles its own server and `rex` CLI under `~/Library/Application Support/com.superlogical.rex/RexServer/Versions/<build>/` (the stowed shim finds it). Config: stowed `~/.config/rex/init.lua` (no hosts there; remote hosts are added in the app, see workflows.md). Both Macs run built-in Tailscale, owner-only, as nodes `ghost-rex` and `silence-rex` (pref `rex.server.tailnet-hostname`, see workflows.md); never enable allow-tailnet-members or allow-anonymous. Install from the dmg with `ditto`; the dmg in Downloads is left in place. |

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
2. **Propose and apply (automatic, on ghost).** Each morning
   `scripts/auto-update.sh` turns a `behind` line into a verified commit that
   bumps the pin, its checksums and the inventory row, then pushes it. See
   [Automatic bumps](#automatic-bumps-ghost). Nothing that fails verification
   reaches the repo.
3. **Apply on the other machines.** That same run updates silence over SSH
   when silence is awake. The box is not updated yet (see the TODO there).
4. **Retain.** After a verified install, `sync-tools.sh` prunes every older
   `~/.local/opt/<tool>-*` and keeps exactly one rollback copy (the version it
   just replaced). The rollback copy is removed by the next upgrade. Nothing
   is pruned unless the new version verified first.

Stow and Postgres are outside this loop by design. Postgres's data directory
is tied to its build, so its old installs are removed by hand, once the
upgrade is verified.

Every pinned CLI has a sha256 pin, checked at install. Where the project
publishes checksums (bun, node, gh, uv, cmake, rustup, claude), they come from
upstream at install time. Otherwise the pin is the sha256 of the release asset,
computed from the download and checked against the GitHub asset digest
(nvim, pnpm, cloudflared) or the build server's `.sha256` (ffmpeg); poppler is
pinned from its tarball, since upstream publishes only a GPG signature.
Self-updating apps (the OpenCode desktop app, ChatGPT, Zed, Cursor, Tailscale)
keep their own update channels. On the Macs, the OpenCode app is the single
source for `opencode` (see the inventory row above), so its CLI cannot lag
behind the server.

## Automatic bumps (ghost)

ghost bumps the pinned tools itself every day at 05:30. The LaunchAgent is
`dev.scozu.auto-update`, template `launchd/dev.scozu.auto-update.plist` (in the
repo, not stowed, so silence never loads it). It runs `scripts/auto-update.sh`:

1. Refuses unless the tree is clean, the branch is `main`, and
   `git pull --ff-only` succeeds.
2. For each pin behind upstream (`check-upstream.sh --latest`), rewrites the
   pin, the `pinsum()` and `ffbuild()` entries for every platform the tool
   has, and the inventory row, through `sync-tools.sh --set-pin`, `--set-sum`
   and `--set-ffbuild`. Nothing else edits the pins.
3. Runs doctor, then sync-tools, then doctor again. It commits only if doctor
   gains no FAIL. Drift a bump causes on purpose is not a new FAIL: the tree
   is dirty before the commit, and silence reports version parity drift until
   it updates.
4. Commits `auto-update: <tool> a -> b, ...`, pushes to `origin main`, then
   runs the silence update over SSH (pull, stow, sync-tools). If silence is
   asleep it logs that and catches up on the next bump.
5. On any failure after the pins change: `git checkout HEAD -- .`, re-runs
   sync-tools to restore the previous versions, logs the failing lines, and
   exits nonzero. Nothing is committed.

If nothing is newer, the run writes one log line and exits.

Flags, for testing: `--dry-run` prints the plan and checksums and changes
nothing; `--no-commit` runs the whole bump, prints the diff, then restores the
tree; `--only TOOL` limits either to one tool.

**Log**: `~/.local/state/auto-update.log` (appended, timestamped). The
LaunchAgent's own stdout and stderr go to `~/.local/state/auto-update.launchd.log`.
After a crash, a stale lock blocks runs: `rmdir ~/.local/state/auto-update.lock`.

**Load and unload** (ghost only; not loaded until reviewed):

```sh
mkdir -p ~/.local/state
sed "s|@HOME@|$HOME|g" ~/Developer/environment/launchd/dev.scozu.auto-update.plist \
  > ~/Library/LaunchAgents/dev.scozu.auto-update.plist
plutil -lint ~/Library/LaunchAgents/dev.scozu.auto-update.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.scozu.auto-update.plist   # load
launchctl kickstart gui/$(id -u)/dev.scozu.auto-update                               # run now
launchctl bootout gui/$(id -u)/dev.scozu.auto-update \
  && rm ~/Library/LaunchAgents/dev.scozu.auto-update.plist                           # unload
```

**Revert a bad bump**: revert the auto-update commit, then sync and push:

```sh
cd ~/Developer/environment
git revert <commit>      # restores the old pins, checksums and inventory rows
scripts/sync-tools.sh    # reinstalls the old versions
git push origin main
ssh silence 'zsh -ic "cd ~/Developer/environment && git pull --ff-only -q && stow --no-folding -t \$HOME home && scripts/sync-tools.sh"'
```

The next run proposes the same bump again, so fix the cause, or unload the
agent until the fix lands.

**TODO (the box, Linux):** auto-update does not reach the box, which has no
SSH alias from ghost. After each auto-update commit, run
`git pull --ff-only && scripts/sync-tools.sh` on the box, or use the ghost-env
`repo_pull` and `sync_tools_check` tools.

OpenCode is not part of this loop: on the Macs it follows the desktop app (see
the `opencode (Macs)` row above).

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
