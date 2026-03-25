# AGENTS

This repository is the canonical, reproducible source of truth for shell, editor, and app configs.

## Principles

- Treat this repository as the configuration root (`./.config` and paths documented below).
- Home directory targets should be symlinks into this repo via `stow` (or equivalent), not separate copies.
- Commit changes here so the setup stays shareable and reproducible.
- Do not keep or generate backup config files in the repo (for example `settings_backup.json`).

## Cursor

- Persistent agent guidance for this workspace lives in `./.cursor/rules/` (`.mdc` files with frontmatter).
- Optional project skills: `./.cursor/skills/<name>/SKILL.md` (not used yet; add when you want versioned skills in-repo).
- Do not add files under `~/.cursor/skills-cursor/` — that tree is reserved for Cursor.

## Zed

- Store the full Zed config in `./.config/zed`.
- `~/.config/zed` must be a symlink to `./.config/zed`.
- Extensions (including Karasu) live in `./.config/zed/extensions` and should be committed.

## Neovim, Ghostty, tmux

- Config lives under `./.config/` (nvim, ghostty, tmux) and is stowed into `~/.config/`.

## OpenCode (optional)

- Config in-repo: `./.config/opencode`. Stow links `~/.config/opencode` when you use this package; omit that symlink if you do not use OpenCode.
- Prefer a single canonical root; avoid `~/.opencode` as a second config root.

## Codex CLI (optional)

- In-repo copy: `./.codex/` (for Codex CLI users who symlink it manually). It is **not** stowed to `~/.codex` by default.
- Do not commit Codex runtime data (sessions, auth, logs, sqlite, caches).

## Karasu theme

- Source of truth: [github.com/scozu/karasu](https://github.com/scozu/karasu); local dev checkout: `~/Developer/karasu`.
- Run `./scripts/update-karasu.sh` to sync Karasu into this repo (Zed, OpenCode config paths, Ghostty).
- Run `./scripts/update-karasu.sh --from-github` to validate or update like a typical install.
- Default Neovim colorscheme tracks `scozu/karasu`; use `KARASU_LOCAL_DEV=1 nvim` only when debugging local Karasu changes.
- The same script refreshes Neovim’s lazy.nvim Karasu checkout and updates `.config/nvim/lazy-lock.json` to the synced commit.

## Workflow

- Prefer `stow -R -t ~ environment` (from `~/Developer`) to refresh symlinks.
- If real files sit under `~/.config` instead of symlinks, move them into this repo and re-stow.

## Tooling defaults

- Prefer `bun` over `npm` / `pnpm` unless the project requires otherwise (see `.cursor/rules/bun-tooling.mdc`).
