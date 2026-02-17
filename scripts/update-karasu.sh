#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/update-karasu.sh [--from-github] [--source PATH] [--skip-cursor]

Options:
  --from-github   Clone Karasu from GitHub instead of using ~/Developer/karasu.
  --source PATH   Use a specific local Karasu checkout.
  --skip-cursor   Skip Cursor extension install/update.
  -h, --help      Show this help message.
EOF
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KARASU_GIT_URL="https://github.com/scozu/karasu.git"
KARASU_LOCAL_DEFAULT="$HOME/Developer/karasu"
NVIM_PLUGIN_DIR="$HOME/.local/share/nvim/lazy/karasu"
NVIM_LOCKFILE="$REPO_ROOT/.config/nvim/lazy-lock.json"

SOURCE_DIR="$KARASU_LOCAL_DEFAULT"
USE_GITHUB=0
SKIP_CURSOR=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-github)
      USE_GITHUB=1
      shift
      ;;
    --source)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --source"
        exit 1
      fi
      SOURCE_DIR="$2"
      shift 2
      ;;
    --skip-cursor)
      SKIP_CURSOR=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if ! command -v bun >/dev/null 2>&1; then
  echo "bun is required but was not found on PATH."
  exit 1
fi

tmp_dir=""
cleanup() {
  if [[ -n "$tmp_dir" && -d "$tmp_dir" ]]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT

clone_temp_karasu() {
  tmp_dir="$(mktemp -d)"
  git clone --depth 1 "$KARASU_GIT_URL" "$tmp_dir/karasu" >/dev/null
  printf '%s' "$tmp_dir/karasu"
}

if [[ "$USE_GITHUB" -eq 1 ]]; then
  source_repo="$(clone_temp_karasu)"
else
  if [[ -d "$SOURCE_DIR/.git" ]]; then
    git -C "$SOURCE_DIR" fetch origin >/dev/null || true
    if ! git -C "$SOURCE_DIR" pull --ff-only >/dev/null; then
      echo "Could not fast-forward $SOURCE_DIR; using current checkout."
    fi
    source_repo="$SOURCE_DIR"
  else
    source_repo="$(clone_temp_karasu)"
  fi
fi

source_rev="$(git -C "$source_repo" rev-parse --short HEAD)"
echo "Using Karasu source: $source_repo ($source_rev)"

(cd "$source_repo" && bun run ./scripts/build-themes.mjs >/dev/null && bun run ./scripts/check-consistency.mjs >/dev/null)

install -d "$REPO_ROOT/.config/ghostty/themes"
install -d "$REPO_ROOT/.config/opencode/themes"
install -d "$REPO_ROOT/.config/zed/extensions/karasu"

cp "$source_repo/platforms/ghostty/karasu-night" "$REPO_ROOT/.config/ghostty/themes/karasu-night"
cp "$source_repo/platforms/ghostty/karasu-snow" "$REPO_ROOT/.config/ghostty/themes/karasu-snow"
cp "$source_repo/platforms/opencode/themes/karasu-night.json" "$REPO_ROOT/.config/opencode/themes/karasu-night.json"
cp "$source_repo/platforms/opencode/themes/karasu-snow.json" "$REPO_ROOT/.config/opencode/themes/karasu-snow.json"
rsync -a --delete "$source_repo/platforms/zed/" "$REPO_ROOT/.config/zed/extensions/karasu/"

if [[ -f "$NVIM_LOCKFILE" ]] && command -v jq >/dev/null 2>&1; then
  tmp_lock="$(mktemp)"
  jq --arg rev "$(git -C "$source_repo" rev-parse HEAD)" '.karasu.commit = $rev' "$NVIM_LOCKFILE" > "$tmp_lock"
  mv "$tmp_lock" "$NVIM_LOCKFILE"
fi

if command -v nvim >/dev/null 2>&1; then
  if [[ -d "$NVIM_PLUGIN_DIR/.git" ]] && [[ -n "$(git -C "$NVIM_PLUGIN_DIR" status --porcelain)" ]]; then
    git -C "$NVIM_PLUGIN_DIR" stash push -m "update-karasu auto-stash" >/dev/null
    echo "Neovim Karasu plugin had local edits; stashed before update."
  fi
  if ! nvim --headless '+Lazy! sync karasu' +qa >/dev/null 2>&1; then
    echo "Warning: Neovim Lazy sync for Karasu failed; run: nvim --headless '+Lazy! sync karasu' +qa"
  fi
fi

if [[ "$SKIP_CURSOR" -eq 0 ]] && command -v cursor >/dev/null 2>&1; then
  if ! cursor --install-extension scozu.karasu-theme --force >/dev/null 2>&1; then
    vsix_path="$source_repo/platforms/vscode/karasu-theme.vsix"
    (
      cd "$source_repo/platforms/vscode"
      bun install --frozen-lockfile >/dev/null
      bun x @vscode/vsce package --out "$vsix_path" >/dev/null
    )
    cursor --install-extension "$vsix_path" --force >/dev/null
  fi
  echo "Cursor extension: installed/updated"
fi

echo "Karasu themes synced into dotfiles."
echo "Run: (cd \"$HOME/Developer\" && stow -R -t ~ environment)"
