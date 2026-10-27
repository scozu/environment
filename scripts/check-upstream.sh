#!/usr/bin/env bash
# check-upstream — read-only report of which pinned tools are behind their
# upstream release. Installs nothing; a bump is a reviewed commit (pin +
# inventory), then sync-tools.sh applies it. Pins come from
# `sync-tools.sh --pins`, so the pins live in one place. Exit 0 always:
# this is a report, not a gate. Needs network.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"

gh_latest() { # gh_latest OWNER/REPO -> upstream tag of the latest release
  curl -fsSL -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$1/releases/latest" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])'
}

latest_of() { # latest_of TOOL -> bare upstream version, or nothing
  case "$1" in
    nvim) gh_latest neovim/neovim | sed 's/^v//' ;;
    pnpm) gh_latest pnpm/pnpm | sed 's/^v//' ;;
    bun)  gh_latest oven-sh/bun | sed 's/^bun-v//' ;;
    gh)   gh_latest cli/cli | sed 's/^v//' ;;
    cloudflared) gh_latest cloudflare/cloudflared ;;
    claude) curl -fsSL https://downloads.claude.ai/claude-code-releases/latest ;;
    # node stays on the 24.x LTS line; index.json is newest-first
    node) curl -fsSL https://nodejs.org/dist/index.json \
            | python3 -c 'import json,sys; print([e["version"] for e in json.load(sys.stdin) if e["version"].startswith("v24.")][0].lstrip("v"))' ;;
  esac
}

behind=0
while read -r t pinned; do
  latest="$(latest_of "$t" 2>/dev/null)"
  if [ -z "$latest" ]; then
    printf '  unknown %s (pinned %s): upstream unreachable\n' "$t" "$pinned"
  elif [ "$latest" = "$pinned" ]; then
    printf '  current %s %s\n' "$t" "$pinned"
  else
    printf '  behind  %s %s -> %s\n' "$t" "$pinned" "$latest"
    behind=$((behind + 1))
  fi
done < <("$REPO/scripts/sync-tools.sh" --pins)

echo "$behind behind"
