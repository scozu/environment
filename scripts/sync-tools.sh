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
# Covers direct release tools: nvim, pnpm, bun, node, gh, cloudflared, claude,
# ffmpeg, rustup, cmake, and poppler. rustup, cmake, and poppler are macOS
# only in TOOLS (the box already has a system rustc and apt poppler-utils).
# rustup-init is run in place under ~/.local/opt/rustup — never move that
# directory aside (it holds downloaded toolchains). No default toolchain is
# installed: projects pin via rust-toolchain.toml.
# poppler is a macOS source build (no official macOS binary): pdftotext,
# with a private static freetype and a pinned cmake as a build-only dep.
# Out of scope by design: stow and postgres (source builds — see
# docs/tools.md), opencode (self-updating installer). Run after `git pull`;
# doctor.sh verifies.
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
TOOLS="nvim pnpm bun node gh cloudflared claude ffmpeg rustup cmake poppler"
# the box keeps claude on its native installer (docs/tools.md), already has
# a system rustc, and already has apt poppler-utils, so skip claude, rustup,
# cmake (poppler's build-only dep), and poppler there
[ "$os" = Linux ] && TOOLS="nvim pnpm bun node gh cloudflared ffmpeg"

pin() { case "$1" in    # pinned version, bare semver
  nvim) echo 0.12.6 ;;
  pnpm) echo 12.16.1 ;;
  bun)  echo 1.4.4 ;;
  node) echo 24.22.2 ;;
  gh)   echo 2.103.3 ;;
  cloudflared) echo 2026.10.7 ;;   # sha256 per asset: pinsum()
  claude) echo 2.1.316 ;;
  ffmpeg) echo 9.0.2 ;;   # static build; build ids: ffbuild(), sha256: pinsum()
  rustup) echo 1.29.3 ;;  # rustup-init; no toolchain is installed by the pin
  cmake) echo 4.5.0 ;;    # official Kitware binary; build-only dep of poppler
  poppler) echo 26.11.0 ;;  # source build of pdftotext; private static freetype 2.15.0
esac; }

tag() { case "$1" in    # upstream release tag for the pinned version
  nvim) echo "v$(pin nvim)" ;;
  pnpm) echo "v$(pin pnpm)" ;;
  bun)  echo "bun-v$(pin bun)" ;;
  node) echo "v$(pin node)" ;;
  gh)   echo "v$(pin gh)" ;;
  cloudflared) pin cloudflared ;;   # bare tag, no v
  ffmpeg) echo "$(ffbuild)_$(pin ffmpeg)" ;;   # build-server dir, e.g. 1789931890_9.0.2
  cmake) echo "v$(pin cmake)" ;;
  poppler) echo "poppler-$(pin poppler)" ;;
esac; }

# Version probes never use PATH: a system copy (/usr/bin/node,
# /usr/local/bin/bun) at the pinned version must not hide a missing or stale
# ~/.local/bin link. probe TOOL EXE prints EXE's bare version, or nothing.
probe() { local x=$2; case "$1" in
  nvim) "$x" --version 2>/dev/null | head -1 | sed 's/^NVIM v//' ;;
  pnpm|bun) "$x" --version 2>/dev/null ;;
  node) "$x" --version 2>/dev/null | sed 's/^v//' ;;
  gh|cloudflared) "$x" --version 2>/dev/null | head -1 | awk '{print $3}' ;;
  claude) "$x" --version 2>/dev/null | awk '{print $1}' ;;
  ffmpeg) "$x" -version 2>/dev/null | head -1 | awk '{print $3}' | sed 's/-.*//' ;;   # "9.0.2-https://www.martin-riedl.de"
  rustup) "$x" --version 2>/dev/null | head -1 | awk '{print $2}' ;;   # "rustup 1.29.3 (...)"
  cmake) "$x" --version 2>/dev/null | head -1 | awk '{print $3}' ;;    # "cmake version 4.5.0"
  poppler) [ -x "$x" ] && "$x" -v 2>&1 | head -1 | awk '{print $3}' ;;  # "pdftotext version 26.11.0" (stderr)
esac; }
main_entry() { local e; e=$(entries "$1"); e=${e%% *}; echo "$e"; }   # "name:rel" of the primary executable
# installed TOOL: version of the ~/.local/bin link this script manages.
installed() { local e; e=$(main_entry "$1"); probe "$1" "$BIN/${e%%:*}"; }
# opt_version TOOL: version of the install in ~/.local/opt/<tool>, links or not.
opt_version() { local e; e=$(main_entry "$1"); probe "$1" "$OPT/$1/${e#*:}"; }
# links_ok TOOL: every entry point in ~/.local/bin links into ~/.local/opt/<tool>.
links_ok() { local e; for e in $(entries "$1"); do
  [ "$(readlink "$BIN/${e%%:*}" 2>/dev/null)" = "$OPT/$1/${e#*:}" ] || return 1
done; }
link_entries() { local t=$1 e name rel; for e in $(entries "$t"); do
  name="${e%%:*}"; rel="${e#*:}"
  ln -sf "$OPT/$t/$rel" "$BIN/$name"
  # Best-effort: unsigned binaries (nvim) are blocked on first run until
  # approved. Dropping the xattrs matches the documented approval step.
  xattr -d com.apple.quarantine "$OPT/$t/$rel" 2>/dev/null || true
  xattr -d com.apple.provenance "$OPT/$t/$rel" 2>/dev/null || true
done; }

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
  ffmpeg) echo ffmpeg.zip ;;   # plus ffprobe.zip, fetched alongside
  rustup) echo rustup-init ;;
  cmake) echo "cmake-$(pin cmake)-macos-universal.tar.gz" ;;
  poppler) echo "poppler-$(pin poppler).tar.xz" ;;
esac; }

asset_linux() { case "$1" in  # the box: glibc builds, never musl/baseline
  nvim) echo "nvim-linux-$lnv.tar.gz" ;;
  pnpm) echo "pnpm-linux-$lx.tar.gz" ;;
  bun)  echo "bun-linux-$lbun.zip" ;;
  node) echo "node-v$(pin node)-linux-$lx.tar.gz" ;;
  gh)   echo "gh_$(pin gh)_linux_$lgh.tar.gz" ;;
  cloudflared) echo "cloudflared-linux-$lgh" ;;   # raw binary, not an archive
  ffmpeg) echo ffmpeg.zip ;;
  rustup) echo rustup-init ;;
esac; }

url() { case "$1" in
  nvim) echo "https://github.com/neovim/neovim/releases/download/$(tag nvim)/$(asset "$1")" ;;
  pnpm) echo "https://github.com/pnpm/pnpm/releases/download/$(tag pnpm)/$(asset "$1")" ;;
  bun)  echo "https://github.com/oven-sh/bun/releases/download/$(tag bun)/$(asset "$1")" ;;
  node) echo "https://nodejs.org/dist/$(tag node)/$(asset "$1")" ;;
  gh)   echo "https://github.com/cli/cli/releases/download/$(tag gh)/$(asset "$1")" ;;
  cloudflared) echo "https://github.com/cloudflare/cloudflared/releases/download/$(tag cloudflared)/$(asset "$1")" ;;
  claude) echo "https://downloads.claude.ai/claude-code-releases/$(pin claude)/darwin-$mac/claude" ;;
  ffmpeg) echo "https://ffmpeg.martin-riedl.de/download/$(ffplat)/$(tag ffmpeg)/ffmpeg.zip" ;;
  rustup) echo "https://static.rust-lang.org/rustup/archive/$(pin rustup)/$(rustup_triple)/rustup-init" ;;
  cmake) echo "https://github.com/Kitware/CMake/releases/download/$(tag cmake)/$(asset cmake)" ;;
  poppler) echo "https://poppler.freedesktop.org/poppler-$(pin poppler).tar.xz" ;;
esac; }

sums() { case "$1" in     # checksums-file URL, or - when none is published
  nvim) echo - ;;
  pnpm) echo - ;;
  bun)  echo "https://github.com/oven-sh/bun/releases/download/$(tag bun)/SHASUMS256.txt" ;;
  node) echo "https://nodejs.org/dist/$(tag node)/SHASUMS256.txt" ;;
  gh)   echo "https://github.com/cli/cli/releases/download/$(tag gh)/gh_$(pin gh)_checksums.txt" ;;
  claude) echo "https://downloads.claude.ai/claude-code-releases/$(pin claude)/manifest.json" ;;
  cloudflared) echo pinned ;;   # no checksums file; sha256 lives in pinsum()
  ffmpeg) echo pinned ;;        # per-zip .sha256 files exist; mirrored in pinsum()
  rustup) echo "https://static.rust-lang.org/rustup/archive/$(pin rustup)/$(rustup_triple)/rustup-init.sha256" ;;
  cmake) echo "https://github.com/Kitware/CMake/releases/download/$(tag cmake)/cmake-$(pin cmake)-SHA-256.txt" ;;
  poppler) echo pinned ;;   # upstream signs a .sig; sha256 lives in pinsum()
esac; }

# pinsum ASSET: sha256 pinned in this repo, for tools whose sums() is "pinned".
# cloudflared lists sha256s only in its release notes, and for the darwin .tgz
# those notes do not match the uploaded files (the Macs build is re-signed and
# repackaged after the notes are written). So these are GitHub's server-side
# asset digests (API field assets[].digest), cross-checked by downloading;
# the linux ones also match the release notes. Bump them with the pin.
pinsum() { case "$1" in
  cloudflared-darwin-arm64.tgz) echo 3586ccf397e98e5f437e60e7c307ca6ac463e110580503af8bb8e6f9ebf831bd ;;
  cloudflared-darwin-amd64.tgz) echo 02f3edfd87684dd5b705607688e4eb4b323f6e777b81e7b3a85af556aa356848 ;;
  cloudflared-linux-amd64)      echo 1f99fb518b83dec2ba8d870a7cc991d82a77e6196295a3d2754ba17ab9f91872 ;;
  cloudflared-linux-arm64)      echo 3df43aedc9ff291d1735b5cb576cb97e0b157488796db2e32b28aecabb445775 ;;
  # ffmpeg 9.0.2: the build server's <zip>.sha256 files, cross-checked by downloading
  macos/arm64/ffmpeg.zip)        echo c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924 ;;
  macos/arm64/ffprobe.zip)       echo fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6 ;;
  linux/amd64/ffmpeg.zip)        echo fa8ecf4abbd290d98f7d188b8649cc6b391ae209a98452be955a15aab1909d7f ;;
  linux/amd64/ffprobe.zip)       echo 3f428c49070be3d24ec338602b76d412e401ffcb8a5641ef0e729181a232fc32 ;;
  linux/arm64/ffmpeg.zip)        echo 93a76ae90db5474eecdf951a729857c64f3de23567228d6a7d5e6e8e3cd1021b ;;
  linux/arm64/ffprobe.zip)       echo bcbe80fb741c180083327afaf5434812e006b33cacde2016b9aeaf6936128330 ;;
  # poppler 26.11.0: sha256 of the official tarball (upstream publishes a
  # GPG .sig, not a sha256 file), cross-checked by downloading
  poppler-26.11.0.tar.xz)        echo 41c32680160addf5a8dd7a830e4869c01e9f6bee1abb91e44fabd1ba9d7828fb ;;
  # freetype 2.15.0: private static build dep of poppler, official savannah tarball
  freetype-2.15.0.tar.gz)        echo 9186627467a616d9a9e3e574748ac0c45fa77398e6364edef3041a8ba8d92f64 ;;
esac; }

# ffmpeg: static builds from Martin Riedl's build server (ffmpeg.martin-riedl.de;
# upstream FFmpeg publishes source only). One platform branch per supported
# machine: macOS arm64 (ghost, silence) and Linux amd64/arm64 (the box). Each
# release has a build-id directory per platform; bump these with the pin.
ffplat() {
  if [ "$os" = Linux ]; then echo "linux/$lgh"
  elif [ "$arch" = arm64 ]; then echo macos/arm64
  else echo unsupported; fi
}
ffbuild() { case "$(ffplat)" in
  macos/arm64) echo 1789931890 ;;
  linux/amd64) echo 1789931100 ;;
  linux/arm64) echo 1789931697 ;;
esac; }

# rustup-init is archived by target tuple. Linux gnu builds are in url/sums
# so the box can opt in later; TOOLS only includes rustup on Darwin.
rustup_triple() {
  if [ "$os" = Linux ]; then
    case "$arch" in
      x86_64)        echo x86_64-unknown-linux-gnu ;;
      aarch64|arm64) echo aarch64-unknown-linux-gnu ;;
      *)             echo unsupported ;;
    esac
  else
    case "$arch" in
      arm64)  echo aarch64-apple-darwin ;;
      x86_64) echo x86_64-apple-darwin ;;
      *)      echo unsupported ;;
    esac
  fi
}

entries() { case "$1" in   # "name:path-inside-opt" pairs, one link each
  nvim) echo "nvim:bin/nvim" ;;
  pnpm) echo "pnpm:pnpm" ;;
  bun)  echo "bun:bun bunx:bun" ;;
  node) echo "node:bin/node npm:bin/npm npx:bin/npx" ;;
  gh)   echo "gh:bin/gh" ;;
  cloudflared) echo "cloudflared:bin/cloudflared" ;;
  claude) echo "claude:bin/claude" ;;
  ffmpeg) echo "ffmpeg:bin/ffmpeg ffprobe:bin/ffprobe" ;;
  rustup) echo "rustup:cargo/bin/rustup cargo:cargo/bin/cargo rustc:cargo/bin/rustc rustfmt:cargo/bin/rustfmt cargo-clippy:cargo/bin/cargo-clippy clippy-driver:cargo/bin/clippy-driver" ;;
  cmake) echo "cmake:CMake.app/Contents/bin/cmake" ;;
  poppler) echo "pdftotext:bin/pdftotext" ;;
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
    if [ "$have" = "$(pin "$t")" ] && links_ok "$t"; then
      printf '  ok    %s %s\n' "$t" "$have"
    elif [ "$have" = "$(pin "$t")" ]; then
      printf '  FAIL  %s %s, but not every ~/.local/bin link points into ~/.local/opt/%s\n' "$t" "$have" "$t"
      rc=1
    else
      printf '  FAIL  %s: %s, pinned %s\n' "$t" "${have:-not installed}" "$(pin "$t")"
      rc=1
    fi
  done
  exit $rc
fi

for t in $TOOLS; do
  have="$(installed "$t")"
  if [ "$have" = "$(pin "$t")" ] && links_ok "$t"; then
    echo "ok    $t $have (already pinned)"
    continue
  fi
  # Pinned build already in ~/.local/opt, only links missing or stale: relink.
  if [ "$(opt_version "$t")" = "$(pin "$t")" ]; then
    link_entries "$t"
    if [ "$(installed "$t")" = "$(pin "$t")" ] && links_ok "$t"; then
      echo "ok    $t $(pin "$t") (relinked ~/.local/bin)"
      continue
    fi
  fi
  echo "== $t: ${have:-not installed} -> $(pin "$t") =="

  file="$(asset "$t")"
  [ "$t" = ffmpeg ] && [ -z "$(ffbuild)" ] && die "ffmpeg: no pinned build for $os $arch (macOS arm64 or Linux only)"
  echo "  download $file"
  curl -fL --retry 2 -o "$TMP/$file" "$(url "$t")" \
    || die "$t: download failed: $(url "$t")"

  if [ "$t" = "ffmpeg" ]; then
    # two single-binary zips: ffmpeg.zip (above) and ffprobe.zip beside it
    curl -fL --retry 2 -o "$TMP/ffprobe.zip" "$(dirname "$(url "$t")")/ffprobe.zip" \
      || die "$t: ffprobe download failed"
    for z in ffmpeg.zip ffprobe.zip; do
      echo "  verify $z against the pinned sha256"
      want="$(pinsum "$(ffplat)/$z")"
      [ -n "$want" ] || die "$t: no pinned sha256 for $(ffplat)/$z"
      printf '%s  %s\n' "$want" "$z" | (cd "$TMP" && shasum -a 256 -c -) \
        || die "$t: checksum verification failed ($z)"
      unzip -q -o "$TMP/$z" -d "$TMP/ffbin" || die "$t: unzip $z failed"
    done
    if [ "$os" = Darwin ]; then
      for b in ffmpeg ffprobe; do
        codesign --verify --strict "$TMP/ffbin/$b" || die "$t: $b signature verification failed"
        codesign -dv "$TMP/ffbin/$b" 2>&1 | grep -q 'TeamIdentifier=KU3N25YGLU' \
          || die "$t: $b has an unexpected signing team"
      done
    fi
  elif [ "$t" = "claude" ]; then
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

  # rustup: run rustup-init into ~/.local/opt/rustup/{rustup,cargo} in place.
  # Never move that directory aside — RUSTUP_HOME holds downloaded toolchains.
  if [ "$t" = "rustup" ]; then
    [ "$(rustup_triple)" != unsupported ] || die "$t: no rustup-init for $os $arch"
    echo "  install rustup-init into $OPT/rustup (in place; toolchains are kept)"
    chmod +x "$TMP/$file"
    xattr -d com.apple.quarantine "$TMP/$file" 2>/dev/null || true
    xattr -d com.apple.provenance "$TMP/$file" 2>/dev/null || true
    mkdir -p "$OPT/rustup"
    RUSTUP_HOME="$OPT/rustup/rustup" CARGO_HOME="$OPT/rustup/cargo" \
      "$TMP/$file" --no-modify-path -y --default-toolchain none \
      || die "$t: rustup-init failed"
    echo "  link entry points"
    link_entries "$t"
    # keep --check meaningful: rustup must not self-update off the pin
    RUSTUP_HOME="$OPT/rustup/rustup" CARGO_HOME="$OPT/rustup/cargo" \
      "$BIN/rustup" set auto-self-update disable \
      || die "$t: could not disable auto-self-update"
    have="$(installed "$t")"
    if [ "$have" = "$(pin "$t")" ]; then
      echo "  installed $t $have"
    else
      die "$t: installed but $BIN/$(main_entry "$t" | cut -d: -f1) reads '${have:-nothing}' — check the link and quarantine"
    fi
    continue
  fi

  # poppler: no official macOS binary. Minimal source build of pdftotext
  # (Qt/glib/cairo/NSS/gpgme/curl/boost/image-codecs/tests off; generic
  # fonts so fontconfig and harfbuzz are not needed). The only extra
  # library is a private static freetype, discarded after link. cmake is
  # a pinned official binary already on PATH from the cmake tool above.
  # Build into a staging prefix and swap only after pdftotext verifies,
  # so a failed compile does not remove a working install.
  if [ "$t" = "poppler" ]; then
    [ "$os" = Darwin ] || die "$t: macOS only"
    cmake_bin="$BIN/cmake"
    [ -x "$cmake_bin" ] || die "$t: cmake $(pin cmake) is required (build-only dep) but $cmake_bin is missing"
    [ "$(probe cmake "$cmake_bin")" = "$(pin cmake)" ] \
      || die "$t: $cmake_bin is $(probe cmake "$cmake_bin"), pinned cmake is $(pin cmake)"
    ftver=2.15.0
    ftfile="freetype-$ftver.tar.gz"
    ftsum="$(pinsum "$ftfile")"
    [ -n "$ftsum" ] || die "$t: no pinned sha256 for $ftfile"
    jobs=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)

    echo "  extract $(asset poppler)"
    mkdir -p "$TMP/pop-src"
    python3 -c 'import tarfile,sys; tarfile.open(sys.argv[1]).extractall(sys.argv[2])' \
      "$TMP/$file" "$TMP/pop-src" || die "$t: extract failed"
    [ -d "$TMP/pop-src/poppler-$(pin poppler)" ] || die "$t: archive layout changed"

    echo "  download private freetype $ftver (static, not installed to PATH)"
    curl -fL --retry 2 -o "$TMP/$ftfile" \
      "https://download.savannah.gnu.org/releases/freetype/$ftfile" \
      || die "$t: freetype download failed"
    echo "  verify $ftfile against the pinned sha256"
    printf '%s  %s\n' "$ftsum" "$ftfile" | (cd "$TMP" && shasum -a 256 -c -) \
      || die "$t: freetype checksum verification failed"
    mkdir -p "$TMP/ft-src"
    tar -xzf "$TMP/$ftfile" -C "$TMP/ft-src" || die "$t: freetype extract failed"
    [ -d "$TMP/ft-src/freetype-$ftver" ] || die "$t: freetype archive layout changed"

    echo "  build static freetype $ftver"
    "$cmake_bin" -S "$TMP/ft-src/freetype-$ftver" -B "$TMP/ft-build" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$TMP/ft" \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DBUILD_SHARED_LIBS=OFF \
      -DFT_DISABLE_HARFBUZZ=TRUE \
      -DFT_DISABLE_PNG=TRUE \
      -DFT_DISABLE_BZIP2=TRUE \
      -DFT_DISABLE_BROTLI=TRUE \
      -DFT_DISABLE_HVF=TRUE \
      -DFT_REQUIRE_ZLIB=TRUE \
      || die "$t: freetype cmake configure failed"
    "$cmake_bin" --build "$TMP/ft-build" -j "$jobs" || die "$t: freetype build failed"
    "$cmake_bin" --install "$TMP/ft-build" || die "$t: freetype install failed"
    [ -f "$TMP/ft/lib/libfreetype.a" ] || die "$t: static libfreetype.a not produced"

    # poppler calls pkg_check_modules(POPPLER_DATA) unconditionally
    # (falls back to $prefix/share/poppler). A stub lets FindPkgConfig
    # load that macro without adding a pkg-config pin; --version is
    # enough for the find, everything else exits 1 (no .pc files).
    mkdir -p "$TMP/stubbin"
    cat > "$TMP/stubbin/pkg-config" <<'STUB'
#!/bin/sh
case "$1" in
  --version) echo "0.0.0"; exit 0 ;;
esac
exit 1
STUB
    chmod +x "$TMP/stubbin/pkg-config"

    echo "  build poppler $(pin poppler) (pdftotext only, static)"
    "$cmake_bin" -S "$TMP/pop-src/poppler-$(pin poppler)" -B "$TMP/pop-build" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$TMP/pop-dest" \
      -DCMAKE_PREFIX_PATH="$TMP/ft" \
      -DCMAKE_FIND_FRAMEWORK=LAST \
      -DPKG_CONFIG_EXECUTABLE="$TMP/stubbin/pkg-config" \
      -DCMAKE_DISABLE_FIND_PACKAGE_Cairo=ON \
      -DCMAKE_DISABLE_FIND_PACKAGE_PNG=ON \
      -DBUILD_SHARED_LIBS=OFF \

      -DFONT_CONFIGURATION=generic \
      -DENABLE_QT5=OFF \
      -DENABLE_QT6=OFF \
      -DENABLE_GLIB=OFF \
      -DENABLE_GOBJECT_INTROSPECTION=OFF \
      -DENABLE_GTK_DOC=OFF \
      -DENABLE_NSS3=OFF \
      -DENABLE_GPGME=OFF \
      -DENABLE_LIBCURL=OFF \
      -DENABLE_BOOST=OFF \
      -DENABLE_LIBJPEG=OFF \
      -DENABLE_LIBOPENJPEG=OFF \
      -DENABLE_LCMS=OFF \
      -DENABLE_LIBTIFF=OFF \
      -DENABLE_BROTLI=OFF \
      -DENABLE_HARFBUZZ=OFF \
      -DENABLE_CPP=OFF \
      -DENABLE_UTILS=ON \
      -DBUILD_MANUAL_TESTS=OFF \
      -DBUILD_GTK_TESTS=OFF \
      -DBUILD_QT5_TESTS=OFF \
      -DBUILD_QT6_TESTS=OFF \
      -DBUILD_CPP_TESTS=OFF \
      -DRUN_GPERF_IF_PRESENT=OFF \
      || die "$t: cmake configure failed"
    "$cmake_bin" --build "$TMP/pop-build" -j "$jobs" || die "$t: build failed"
    "$cmake_bin" --install "$TMP/pop-build" || die "$t: install to staging failed"
    staged="$TMP/pop-dest/bin/pdftotext"
    have="$(probe poppler "$staged")"
    [ "$have" = "$(pin poppler)" ] || die "$t: staged pdftotext reads '${have:-nothing}', expected $(pin poppler)"
    echo "  staged pdftotext $have"

    echo "  install into $OPT/poppler"
    target="$OPT/poppler"
    rollback=""
    if [ -e "$target" ]; then
      if [ -n "$(installed poppler)" ]; then
        keep="$target-$(echo "$(installed poppler)" | tr -cd '[:alnum:].')"
      else
        keep="$target-unknown"
      fi
      rm -rf "$keep" && mv "$target" "$keep" \
        || die "$t: could not move old install aside"
      echo "  (old install kept for rollback at $keep)"
      rollback="$keep"
    fi
    mv "$TMP/pop-dest" "$target" || die "$t: move staged install failed"
    echo "  link entry points"
    link_entries "$t"
    have="$(installed "$t")"
    if [ "$have" = "$(pin "$t")" ] && links_ok "$t"; then
      echo "  installed $t $have"
      prune_old "$t" "$rollback"
    else
      die "$t: installed but $BIN/$(main_entry "$t" | cut -d: -f1) reads '${have:-nothing}' — check the link"
    fi
    continue
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
  elif [ "$t" = "ffmpeg" ]; then
    mkdir -p "$target/bin"
    mv "$TMP/ffbin/ffmpeg" "$TMP/ffbin/ffprobe" "$target/bin/" || die "$t: move failed"
    chmod +x "$target/bin/ffmpeg" "$target/bin/ffprobe"
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
  link_entries "$t"

  have="$(installed "$t")"
  if [ "$have" = "$(pin "$t")" ]; then
    echo "  installed $t $have"
    prune_old "$t" "$rollback"
  else
    die "$t: installed but $BIN/$(main_entry "$t" | cut -d: -f1) reads '${have:-nothing}' — check the link and quarantine"
  fi
done

echo "sync-tools done"
