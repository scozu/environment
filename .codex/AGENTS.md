# Global Codex Rules

## Tooling Defaults
- Always use `bun` when possible.
- Never use `npm` or `pnpm` unless explicitly required by the project or requested by the user.

## Git Commit Message Rules
- Treat commit messages as durable history: explain intent and impact, not just diff details.
- Use this structure:
  - Subject line
  - Blank line
  - Optional body
- Subject line requirements:
  - Imperative mood (`Add`, `Fix`, `Refactor`, `Remove`)
  - Capitalized first word
  - No trailing period
  - Target <= 50 chars (hard max 72)
- Body requirements (when needed):
  - Wrap at ~72 characters per line
  - Explain what changed and why it was necessary
  - Call out constraints, tradeoffs, and side effects
  - Avoid step-by-step implementation narration when code already shows how
- Use trailers at the end when relevant:
  - `Fixes: #123`
  - `Refs: #456`
- Prefer atomic commits (one logical change per commit).
- Avoid vague subjects like `WIP`, `misc fixes`, `updates`, or `stuff`.
- Validate subject with: `If applied, this commit will <subject>`.
