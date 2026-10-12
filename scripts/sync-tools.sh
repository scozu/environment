#!/usr/bin/env bash
# sync-tools — install or update the direct-installed tools on THIS machine
# to the pinned versions below. Idempotent: tools already at the pinned
# version are skipped without downloading. Runs on ghost or silence.
#
#   scripts/sync-tools.sh          install/update anything missing or stale
#   scripts/sync-tools.sh --check  read-only; exit 1 if anything differs
#                                  (doctor.sh uses this)
#   scripts/sync-tools.sh --pins   read-only; prints "tool version" per pin
#                                  (check-upstream.sh uses this)
#
# Retention: after a verified install, every older opt/<tool>-* is pruned,
# except the one rollback copy moved aside by this run.
#
# Covers the five tarball tools: nvim, pnpm, bun, node, gh. Out of scope by
# design: stow and postgres (source builds — see docs/tools.md), opencode
# (self-updating installer). Run after `git pull`; doctor.sh verifies.
#
# Pins are bare semver for every tool. tag() maps a pin to that project's
# upstream release tag, which differs per project (v1.2.3, bun-v1.2.3).
# Adding or upgrading a tool = edit its pin() line, update the inventory
# table in docs/tools.md, commit. Changing an archive layout = edit asset().

set -u

OPT="$HOME/.local/opt"
BIN="$HOME/.local/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OPT" "$BIN"
PATH="$BIN:$PATH"   # the post-install version check must see what we just linked

arch="$(uname -m)"        # arm64 | x86_64
mac="${arch/x86_64/x64}"  # the x64 naming GitHub/node use for Intel

# ---------------------------------------------------------------- config
TOOLS="nvim pnpm bun node gh"

pin() { case "$1" in    # pinned version, bare semver
  nvim) echo 0.12.6 ;;
  pnpm) echo 12.11.2 ;;
  bun)  echo 1.4.3 ;;
  node) echo 24.21.0 ;;
  gh)   echo 2.102.0 ;;
esac; }

tag() { case "$1" in    # upstream release tag for the pinned version
  nvim) echo "v$(pin nvim)" ;;
  pnpm) echo "v$(pin pnpm)" ;;
  bun)  echo "bun-v$(pin bun)" ;;
  node) echo "v$(pin node)" ;;
  gh)   echo "v$(pin gh)" ;;
esac; }

installed() { case "$1" in    # prints this machine's bare version, or nothing
  nvim) nvim --version 2>/dev/null | head -1 | sed 's/^NVIM v//' ;;
  pnpm) pnpm --version 2>/dev/null ;;
  bun)  bun --version 2>/dev/null ;;
  node) node --version 2>/dev/null | sed 's/^v//' ;;
  gh)   gh --version 2>/dev/null | head -1 | awk '{print $3}' ;;
esac; }

asset() { case "$1" in        # archive filename, arch-aware
  nvim) echo "nvim-macos-$arch.tar.gz" ;;
  pnpm) echo "pnpm-darwin-$mac.tar.gz" ;;
  bun)  echo "bun-darwin-${mac/arm64/aarch64}.zip" ;;   # bun says aarch64
  node) echo "node-v$(pin node)-darwin-$mac.tar.gz" ;;
  gh)   echo "gh_$(pin gh)_macOS_${mac/x64/amd64}.zip" ;;
esac; }

url() { case "$1" in
  nvim) echo "https://github.com/neovim/neovim/releases/download/$(tag nvim)/$(asset "$1")" ;;
  pnpm) echo "https://github.com/pnpm/pnpm/releases/download/$(tag pnpm)/$(asset "$1")" ;;
  bun)  echo "https://github.com/oven-sh/bun/releases/download/$(tag bun)/$(asset "$1")" ;;
  node) echo "https://nodejs.org/dist/$(tag node)/$(asset "$1")" ;;
  gh)   echo "https://github.com/cli/cli/releases/download/$(tag gh)/$(asset "$1")" ;;
esac; }

sums() { case "$1" in     # checksums-file URL, or - when none is published
  nvim) echo - ;;
  pnpm) echo - ;;
  bun)  echo "https://github.com/oven-sh/bun/releases/download/$(tag bun)/SHASUMS256.txt" ;;
  node) echo "https://nodejs.org/dist/$(tag node)/SHASUMS256.txt" ;;
  gh)   echo "https://github.com/cli/cli/releases/download/$(tag gh)/gh_$(pin gh)_checksums.txt" ;;
esac; }

entries() { case "$1" in   # "name:path-inside-opt" pairs, one link each
  nvim) echo "nvim:bin/nvim" ;;
  pnpm) echo "pnpm:pnpm" ;;
  bun)  echo "bun:bun bunx:bun" ;;
  node) echo "node:bin/node npm:bin/npm npx:bin/npx" ;;
  gh)   echo "gh:bin/gh" ;;
esac; }

# ---------------------------------------------------------------- engine
die() { echo "sync-tools: $1" >&2; exit 1; }

# prune_old TOOL KEEP: remove superseded installs; KEEP is this run's rollback
prune_old() {
  local d
  for d in "$OPT/$1"-*; do
    [ -e "$d" ] || continue
    [ "$d" = "${2:-}" ] && continue
    rm -rf "$d" && echo "  pruned $(basename "$d")"
  done
}

if [ "${1:-}" = "--pins" ]; then
  for t in $TOOLS; do echo "$t $(pin "$t")"; done
  exit 0
fi

if [ "${1:-}" = "--check" ]; then
  rc=0
  for t in $TOOLS; do
    have="$(installed "$t")"
    if [ "$have" = "$(pin "$t")" ]; then
      printf '  ok    %s %s\n' "$t" "$have"
    else
      printf '  FAIL  %s: %s, pinned %s\n' "$t" "${have:-not installed}" "$(pin "$t")"
      rc=1
    fi
  done
  exit $rc
fi

for t in $TOOLS; do
  have="$(installed "$t")"
  if [ "$have" = "$(pin "$t")" ]; then
    echo "ok    $t $have (already pinned)"
    continue
  fi
  echo "== $t: ${have:-not installed} -> $(pin "$t") =="

  file="$(asset "$t")"
  echo "  download $file"
  curl -fL --retry 2 -o "$TMP/$file" "$(url "$t")" \
    || die "$t: download failed: $(url "$t")"

  if [ "$(sums "$t")" != "-" ]; then
    echo "  verify $file"
    curl -fsSL "$(sums "$t")" | grep "$file" | (cd "$TMP" && shasum -a 256 -c -) \
      || die "$t: checksum verification failed"
  else
    echo "  ($t publishes no checksums — pinned URL only)"
  fi

  echo "  install into $OPT/$t"
  target="$OPT/$t"
  rollback=""
  if [ -e "$target" ]; then
    if [ -n "$have" ]; then
      keep="$target-$(echo "$have" | tr -cd '[:alnum:].')"
    else
      keep="$target-unknown"
    fi
    rm -rf "$keep" && mv "$target" "$keep" \
      || die "$t: could not move old install aside"
    echo "  (old install kept for rollback at $keep)"
    rollback="$keep"
  fi

  if [ "$t" = "pnpm" ]; then
    # pnpm's archive has no top-level dir; extract straight into opt/pnpm
    mkdir -p "$target"
    tar -xzf "$TMP/$file" -C "$target" || die "$t: extract failed"
  else
    dir="${file%.zip}"; dir="${dir%.tar.gz}"
    mkdir -p "$TMP/extract"
    if [ "${file%.zip}" != "$file" ]; then
      unzip -q -o "$TMP/$file" -d "$TMP/extract" || die "$t: unzip failed"
    else
      tar -xzf "$TMP/$file" -C "$TMP/extract" || die "$t: extract failed"
    fi
    [ -d "$TMP/extract/$dir" ] || die "$t: archive layout changed (expected $dir/)"
    mv "$TMP/extract/$dir" "$target" || die "$t: move failed"
  fi

  echo "  link entry points"
  for e in $(entries "$t"); do
    name="${e%%:*}"; rel="${e#*:}"
    ln -sf "$target/$rel" "$BIN/$name"
    # Best-effort: unsigned binaries (nvim) are blocked on first run until
    # approved. Dropping the xattrs matches the documented approval step.
    xattr -d com.apple.quarantine "$target/$rel" 2>/dev/null || true
    xattr -d com.apple.provenance "$target/$rel" 2>/dev/null || true
  done

  have="$(installed "$t")"
  if [ "$have" = "$(pin "$t")" ]; then
    echo "  installed $t $have"
    prune_old "$t" "$rollback"
  else
    die "$t: installed but version reads '${have:-nothing}' — check PATH and quarantine"
  fi
done

echo "sync-tools done"
