#!/usr/bin/env bash
# sync-tools — install or update the direct-installed tools on THIS machine
# to the pinned versions below. Idempotent: tools already at the pinned
# version are skipped without downloading. Runs on ghost, silence (macOS),
# or the box (Linux, x86_64 or aarch64) — asset() picks the platform build.
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
# Covers direct release tools: nvim, pnpm, bun, node, gh, cloudflared, claude. Out
# of scope by
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

os="$(uname -s)"          # Darwin (ghost, silence) | Linux (the box)
arch="$(uname -m)"        # arm64 | x86_64 (macOS); x86_64 | aarch64 (Linux)
mac="${arch/x86_64/x64}"  # the x64 naming GitHub/node use for Intel
if [ "$os" = Linux ]; then
  case "$arch" in
    x86_64)        lx=x64;   lgh=amd64; lnv=x86_64; lbun=x64 ;;
    aarch64|arm64) lx=arm64; lgh=arm64; lnv=arm64;  lbun=aarch64 ;;
    *) echo "sync-tools: unsupported Linux arch $arch" >&2; exit 1 ;;
  esac
fi

# ---------------------------------------------------------------- config
TOOLS="nvim pnpm bun node gh cloudflared claude"
# the box keeps claude on its native installer (docs/tools.md), so skip it there
[ "$os" = Linux ] && TOOLS="nvim pnpm bun node gh cloudflared"

pin() { case "$1" in    # pinned version, bare semver
  nvim) echo 0.12.6 ;;
  pnpm) echo 12.11.2 ;;
  bun)  echo 1.4.3 ;;
  node) echo 24.21.0 ;;
  gh)   echo 2.102.0 ;;
  cloudflared) echo 2026.10.5 ;;   # sha256 per asset: pinsum()
  claude) echo 2.1.303 ;;
esac; }

tag() { case "$1" in    # upstream release tag for the pinned version
  nvim) echo "v$(pin nvim)" ;;
  pnpm) echo "v$(pin pnpm)" ;;
  bun)  echo "bun-v$(pin bun)" ;;
  node) echo "v$(pin node)" ;;
  gh)   echo "v$(pin gh)" ;;
  cloudflared) pin cloudflared ;;   # bare tag, no v
esac; }

installed() { case "$1" in    # prints this machine's bare version, or nothing
  nvim) nvim --version 2>/dev/null | head -1 | sed 's/^NVIM v//' ;;
  pnpm) pnpm --version 2>/dev/null ;;
  bun)  bun --version 2>/dev/null ;;
  node) node --version 2>/dev/null | sed 's/^v//' ;;
  gh)   gh --version 2>/dev/null | head -1 | awk '{print $3}' ;;
  cloudflared) cloudflared --version 2>/dev/null | head -1 | awk '{print $3}' ;;
  claude) claude --version 2>/dev/null | awk '{print $1}' ;;
esac; }

asset() {                     # archive filename, platform- and arch-aware
  if [ "$os" = Linux ]; then asset_linux "$1"; return; fi
  case "$1" in
  nvim) echo "nvim-macos-$arch.tar.gz" ;;
  pnpm) echo "pnpm-darwin-$mac.tar.gz" ;;
  bun)  echo "bun-darwin-${mac/arm64/aarch64}.zip" ;;   # bun says aarch64
  node) echo "node-v$(pin node)-darwin-$mac.tar.gz" ;;
  gh)   echo "gh_$(pin gh)_macOS_${mac/x64/amd64}.zip" ;;
  cloudflared) echo "cloudflared-darwin-${mac/x64/amd64}.tgz" ;;
  claude) echo claude ;;
esac; }

asset_linux() { case "$1" in  # the box: glibc builds, never musl/baseline
  nvim) echo "nvim-linux-$lnv.tar.gz" ;;
  pnpm) echo "pnpm-linux-$lx.tar.gz" ;;
  bun)  echo "bun-linux-$lbun.zip" ;;
  node) echo "node-v$(pin node)-linux-$lx.tar.gz" ;;
  gh)   echo "gh_$(pin gh)_linux_$lgh.tar.gz" ;;
  cloudflared) echo "cloudflared-linux-$lgh" ;;   # raw binary, not an archive
esac; }

url() { case "$1" in
  nvim) echo "https://github.com/neovim/neovim/releases/download/$(tag nvim)/$(asset "$1")" ;;
  pnpm) echo "https://github.com/pnpm/pnpm/releases/download/$(tag pnpm)/$(asset "$1")" ;;
  bun)  echo "https://github.com/oven-sh/bun/releases/download/$(tag bun)/$(asset "$1")" ;;
  node) echo "https://nodejs.org/dist/$(tag node)/$(asset "$1")" ;;
  gh)   echo "https://github.com/cli/cli/releases/download/$(tag gh)/$(asset "$1")" ;;
  cloudflared) echo "https://github.com/cloudflare/cloudflared/releases/download/$(tag cloudflared)/$(asset "$1")" ;;
  claude) echo "https://downloads.claude.ai/claude-code-releases/$(pin claude)/darwin-$mac/claude" ;;
esac; }

sums() { case "$1" in     # checksums-file URL, or - when none is published
  nvim) echo - ;;
  pnpm) echo - ;;
  bun)  echo "https://github.com/oven-sh/bun/releases/download/$(tag bun)/SHASUMS256.txt" ;;
  node) echo "https://nodejs.org/dist/$(tag node)/SHASUMS256.txt" ;;
  gh)   echo "https://github.com/cli/cli/releases/download/$(tag gh)/gh_$(pin gh)_checksums.txt" ;;
  claude) echo "https://downloads.claude.ai/claude-code-releases/$(pin claude)/manifest.json" ;;
  cloudflared) echo pinned ;;   # no checksums file; sha256 lives in pinsum()
esac; }

# pinsum ASSET: sha256 pinned in this repo, for tools whose sums() is "pinned".
# cloudflared lists sha256s only in its release notes, and for the darwin .tgz
# those notes do not match the uploaded files (the Macs build is re-signed and
# repackaged after the notes are written). So these are GitHub's server-side
# asset digests (API field assets[].digest), cross-checked by downloading;
# the linux ones also match the release notes. Bump them with the pin.
pinsum() { case "$1" in
  cloudflared-darwin-arm64.tgz) echo 184c7d4f5f977348243a6d7ca8f6cf6073b9b2746cfe8c1fe15aa59e9a522bf0 ;;
  cloudflared-darwin-amd64.tgz) echo 6699392fed92367808c248c2d90bed66e49bbf66e1b4ee3e4141230f3f7391b3 ;;
  cloudflared-linux-amd64)      echo e1bc0cf084fd9e590554fe769a86b1db46701c3f847a43d902f7b974a4e16298 ;;
  cloudflared-linux-arm64)      echo 72e0d05a67e09da87cf495e409a28c3cc5994dd23fc66a982eebea6a55923b7d ;;
esac; }

entries() { case "$1" in   # "name:path-inside-opt" pairs, one link each
  nvim) echo "nvim:bin/nvim" ;;
  pnpm) echo "pnpm:pnpm" ;;
  bun)  echo "bun:bun bunx:bun" ;;
  node) echo "node:bin/node npm:bin/npm npx:bin/npx" ;;
  gh)   echo "gh:bin/gh" ;;
  cloudflared) echo "cloudflared:bin/cloudflared" ;;
  claude) echo "claude:bin/claude" ;;
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

  if [ "$t" = "claude" ]; then
    echo "  verify Claude release manifest and macOS signature"
    curl -fsSL "$(sums "$t")" -o "$TMP/manifest.json" \
      || die "$t: manifest download failed"
    checksum=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["platforms"][sys.argv[2]]["checksum"])' "$TMP/manifest.json" "darwin-$mac") \
      || die "$t: invalid manifest"
    printf '%s  claude\n' "$checksum" | (cd "$TMP" && shasum -a 256 -c -) \
      || die "$t: checksum verification failed"
    chmod +x "$TMP/$file"
    codesign --verify --strict "$TMP/$file" || die "$t: code signature verification failed"
    codesign -dv "$TMP/$file" 2>&1 | grep -q 'TeamIdentifier=Q6L2SF6YDW' \
      || die "$t: unexpected signing team"
  elif [ "$(sums "$t")" = "pinned" ]; then
    echo "  verify $file against the pinned sha256"
    want="$(pinsum "$file")"
    [ -n "$want" ] || die "$t: no pinned sha256 for $file"
    printf '%s  %s\n' "$want" "$file" | (cd "$TMP" && shasum -a 256 -c -) \
      || die "$t: checksum verification failed"
  elif [ "$(sums "$t")" != "-" ]; then
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

  if [ "$t" = "claude" ]; then
    mkdir -p "$target/bin"
    mv "$TMP/$file" "$target/bin/claude" || die "$t: move failed"
  elif [ "$t" = "cloudflared" ]; then
    # Linux ships the raw binary; macOS a .tgz holding just ./cloudflared
    mkdir -p "$target/bin"
    if [ "${file%.tgz}" != "$file" ]; then
      tar -xzf "$TMP/$file" -C "$target/bin" cloudflared || die "$t: extract failed"
    else
      mv "$TMP/$file" "$target/bin/cloudflared" || die "$t: move failed"
    fi
    chmod +x "$target/bin/cloudflared"
  elif [ "$t" = "pnpm" ]; then
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
