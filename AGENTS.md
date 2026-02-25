# AGENTS

This repository is the canonical, reproducible source of truth for all configs.

## Principles
- Treat this repository as the canonical configuration root (`./.config` and `./.codex`).
- Home directory config paths should be symlinks to this repo via `stow` (or equivalent), not separate copies.
- Changes should be made in this repo and committed so the setup is shareable on GitHub.
- Do not keep or generate backup config files in the repo (e.g., `settings_backup.json`).

## Zed
- Store the full Zed config in `./.config/zed`.
- `~/.config/zed` must be a symlink to `./.config/zed`.
- Extensions (including Karasu) live in `./.config/zed/extensions` and should be committed.

## OpenCode
- Store the full OpenCode config in `./.config/opencode`.
- `~/.config/opencode` must be a symlink to `./.config/opencode`.
- Do not use `~/.opencode` as a separate config root; keep a single canonical config in this repo.

## Codex
- Keep shared Codex defaults in `./.codex` (for example `AGENTS.md`, `config.toml`, and `rules/`).
- `~/.codex` should be a symlink to `./.codex`.
- Do not commit Codex runtime or secrets (sessions, auth, logs, sqlite, caches, temp files).

## Karasu Theme
- Karasu source of truth is [github.com/scozu/karasu](https://github.com/scozu/karasu) and local dev checkout is `~/Developer/karasu`.
- Use `./scripts/update-karasu.sh` to sync latest Karasu into this repo (`zed`, `opencode`, `ghostty`).
- Use `./scripts/update-karasu.sh --from-github` to validate/update from GitHub as a typical user flow.
- Keep Neovim on `scozu/karasu` by default; use `KARASU_LOCAL_DEV=1 nvim` only when troubleshooting local changes in `~/Developer/karasu`.
- `./scripts/update-karasu.sh` also refreshes Neovim's lazy.nvim Karasu checkout and updates `.config/nvim/lazy-lock.json` to the synced Karasu commit.

## Workflow
- Prefer `stow -R -t ~ environment` to refresh links.
- If files exist directly under `~/.config` without symlinks, move them into this repo and re-stow.

## Tooling Defaults
- Always use `bun` (never `npm` or `pnpm`).
- Canonical commands:
  - `bun install`
  - `bun run test`
  - `bun run lint`
  - `bun run format`
  - `bun run build`
