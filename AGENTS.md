# AGENTS

This repository is the canonical, reproducible source of truth for all configs.

## Principles
- Treat `~/Developer/environment/.config` as the canonical configuration root.
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
