#!/usr/bin/env bash
# auto-update — bump the pinned tools to their upstream releases on ghost,
# install, verify, commit, push, then update silence. Runs daily from the
# LaunchAgent dev.scozu.auto-update (template: launchd/dev.scozu.auto-update.plist).
#
#   scripts/auto-update.sh               full run
#   scripts/auto-update.sh --dry-run     plan and checksums; changes nothing
#   scripts/auto-update.sh --no-commit   bump, install, doctor, then restore
#   scripts/auto-update.sh --only TOOL   one tool (combines with the above)
#
# A run refuses a dirty tree or a branch other than main, and pulls --ff-only.
# A bump is committed only if doctor.sh shows no new FAIL. Drift a bump creates
# on purpose is not new: the tree is dirty until the commit, and silence is
# behind until it is updated. Any failure after the pins change restores HEAD
# and re-syncs the tools. The box has no SSH alias, so it is not updated here.
# Log: ~/.local/state/auto-update.log. Lock: ~/.local/state/auto-update.lock.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$HOME/.local/state"
LOG="$STATE/auto-update.log"
LOCK="$STATE/auto-update.lock"
PEER=silence
DRY=0 NOCOMMIT=0 ONLY=""
HOLDS_LOCK=0
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; [ "$HOLDS_LOCK" = 1 ] && rmdir "$LOCK"; }
trap cleanup EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --no-commit) NOCOMMIT=1 ;;
    --only) ONLY="${2:?--only needs a tool name}"; shift ;;
    *) echo "usage: auto-update.sh [--dry-run] [--no-commit] [--only TOOL]" >&2; exit 2 ;;
  esac
  shift
done

REALSYNC="$REPO/scripts/sync-tools.sh"
UPSTREAM="$REPO/scripts/check-upstream.sh"
DOCTOR="$REPO/scripts/doctor.sh"
SYNC="$REALSYNC"
if [ "$DRY" = 1 ]; then   # a dry run rewrites a scratch copy of the pins only
  cp "$REALSYNC" "$TMP/sync-tools.sh" && chmod +x "$TMP/sync-tools.sh" || exit 1
  SYNC="$TMP/sync-tools.sh"
fi

mkdir -p "$STATE"
say() { # say MESSAGE: stdout, and the log unless --dry-run
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') $*"
  echo "$line"
  [ "$DRY" = 1 ] || echo "$line" >>"$LOG"
}
log_tail() { tail -n 3 "$1" | while IFS= read -r l; do say "  $l"; done; }

if [ "$DRY" = 0 ]; then
  mkdir "$LOCK" 2>/dev/null || { say "skipped: another run holds $LOCK"; exit 1; }
  HOLDS_LOCK=1
fi

refuse() { # refuse MESSAGE: a real run stops; a dry run only notes it
  if [ "$DRY" = 1 ]; then say "note: $* (a real run refuses)"; else say "refused: $*"; exit 1; fi
}

cd "$REPO" || exit 1
branch="$(git branch --show-current)"
[ "$branch" = main ] || refuse "branch is '$branch', not main"
[ -z "$(git status --porcelain)" ] || refuse "working tree is not clean"
if [ "$DRY" = 0 ] && ! git pull --ff-only -q; then say "refused: git pull --ff-only failed"; exit 1; fi

restore_tree() { # back to HEAD's pins, and the tools back to them
  git checkout -q HEAD -- .
  if "$REALSYNC" >"$TMP/restore.out" 2>&1; then say "restored: tree at HEAD, tools synced to its pins"
  else say "restore: scripts/sync-tools.sh failed, run it by hand:"; log_tail "$TMP/restore.out"; fi
}

fail() { # fail MESSAGE: restore the committed pins (not on a dry run), exit 1
  say "failed: $*"
  [ "$DRY" = 1 ] || restore_tree
  exit 1
}

platforms_of() { # platforms_of TOOL -> the "OS:arch" entries its checksums cover
  case "$1" in
    cloudflared) echo "Darwin:arm64 Darwin:x86_64 Linux:x86_64 Linux:aarch64" ;;
    nvim|pnpm|ffmpeg|bun|node|gh|uv) echo "Darwin:arm64 Linux:x86_64 Linux:aarch64" ;;
    *) echo "Darwin:arm64" ;;   # poppler, rustup, cmake, claude: macOS in TOOLS
  esac
}

describe() { # describe OS:ARCH TOOL FIELD -> one field of sync-tools --describe
  ST_OS="${1%:*}" ST_ARCH="${1#*:}" "$SYNC" --describe "$2" | sed -n "s/^$3=//p"
}

ffmpeg_ready() { # ffmpeg_ready VERSION: every platform's latest build is VERSION
  local p
  for p in macos/arm64 linux/amd64 linux/arm64; do
    [ "$("$UPSTREAM" --ffmpeg-build "$p" | awk '{print $2}')" = "$1" ] || return 1
  done
}

dl_sha() { # dl_sha URL -> sha256 of the download
  rm -f "$TMP/blob"
  curl -fsSL --retry 2 -o "$TMP/blob" "$1" && shasum -a 256 "$TMP/blob" | awk '{print $1}'
}

published_sha() { # published_sha URL -> sha256 the publisher lists for URL, or nothing
  case "$1" in
    https://github.com/*/releases/download/*)   # the GitHub asset digest
      local rest repo tag
      rest="${1#https://github.com/}"; repo="${rest%%/releases/download/*}"
      tag="${rest#*/releases/download/}"; tag="${tag%%/*}"
      curl -fsSL -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/$repo/releases/tags/$tag" 2>/dev/null \
        | python3 -c 'import json,sys
name = sys.argv[1]
d = next((a.get("digest") or "" for a in json.load(sys.stdin)["assets"] if a["name"] == name), "")
print(d[7:] if d.startswith("sha256:") else "")' "${1##*/}" ;;
    *) curl -fsSL "$1.sha256" 2>/dev/null | awk 'NR==1 && length($1) == 64 {print $1}' ;;
  esac
}

listed_sha() { # listed_sha SUMS_URL ASSET -> sha256 the project's checksum file lists for ASSET
  curl -fsSL "$1" 2>/dev/null \
    | awk -v f="$2" '{n = $NF; sub(/^\*/, "", n)} n == f && length($1) == 64 {print $1; exit}'
}

pinned_sum() { # pinned_sum TOOL SPEC KEY URL: download URL, check it against the publisher, pin it under KEY
  local t=$1 spec=$2 key=$3 url=$4 sha pub
  sha="$(dl_sha "$url")" && [ -n "$sha" ] || { say "fail $t: download failed: $url"; return 1; }
  pub="$(published_sha "$url")"
  if [ -n "$pub" ] && [ "$pub" != "$sha" ]; then
    say "fail $t: $key is $sha, the publisher lists $pub"; return 1
  fi
  "$SYNC" --set-sum "$key" "$sha" || return 1
  say "  $t ${spec%:*}/${spec#*:} $key sha256 $sha${pub:+ (matches the publisher)}"
}

bump_one() { # bump_one TOOL OLD NEW: pin, build ids and checksums of NEW, written to $SYNC
  local t=$1 old=$2 new=$3 spec url key sums asset sha plat oldb newb
  "$SYNC" --set-pin "$t" "$new" || return 1
  if [ "$t" = poppler ]; then "$SYNC" --set-sum "poppler-$old.tar.xz" "" || return 1; fi
  if [ "$t" = ffmpeg ]; then
    for spec in $(platforms_of ffmpeg); do
      plat="$(describe "$spec" ffmpeg key)"; plat="${plat%/ffmpeg.zip}"
      oldb="$(describe "$spec" ffmpeg url | sed 's#.*/\([0-9]*\)_[^/]*/ffmpeg.zip#\1#')"
      read -r newb _ <<<"$("$UPSTREAM" --ffmpeg-build "$plat")"
      [ -n "$newb" ] || return 1
      "$SYNC" --set-ffbuild "$plat" "$newb" || return 1
      echo "ffmpeg $oldb $newb" >>"$TMP/docpairs"
    done
  fi
  for spec in $(platforms_of "$t"); do
    url="$(describe "$spec" "$t" url)"; key="$(describe "$spec" "$t" key)"
    sums="$(describe "$spec" "$t" sums)"; asset="$(describe "$spec" "$t" asset)"
    [ -n "$url" ] || return 1
    case "$sums" in
      pinned)
        pinned_sum "$t" "$spec" "$key" "$url" || return 1
        if [ "$t" = ffmpeg ]; then
          pinned_sum "$t" "$spec" "${key%ffmpeg.zip}ffprobe.zip" "${url%ffmpeg.zip}ffprobe.zip" || return 1
        fi ;;
      -) ;;
      *manifest.json)   # claude: the release manifest, darwin-arm64 only
        sha="$(curl -fsSL "$sums" | python3 -c 'import json,sys; print(json.load(sys.stdin)["platforms"]["darwin-arm64"]["checksum"])')"
        [ -n "$sha" ] || { say "fail $t: no darwin-arm64 checksum in $sums"; return 1; }
        say "  $t ${spec%:*}/${spec#*:} $asset sha256 $sha (published)" ;;
      *)
        sha="$(listed_sha "$sums" "$asset")"
        [ -n "$sha" ] || { say "fail $t: $asset is not listed in $sums"; return 1; }
        say "  $t ${spec%:*}/${spec#*:} $asset sha256 $sha (published)" ;;
    esac
  done
}

doc_rewrite() { # doc_rewrite TOOL OLD NEW: OLD -> NEW in TOOL's inventory row of docs/tools.md
  python3 - "$REPO/docs/tools.md" "$1" "$2" "$3" <<'PY'
import sys
path, tool, old, new = sys.argv[1:5]
lines = open(path).read().split('\n')
hits = [i for i, l in enumerate(lines) if l.startswith(f'| {tool} |')]
if len(hits) != 1:
    sys.exit(f'auto-update: docs/tools.md has {len(hits)} rows for {tool}')
lines[hits[0]] = lines[hits[0]].replace(old, new)
open(path, 'w').write('\n'.join(lines))
PY
}

gate_fails() { # gate_fails DOCTOR_OUTPUT: the FAIL lines that count for the gate
  grep '^  FAIL  ' "$1" | grep -vE 'working tree clean|in sync with origin|: local .*, '"$PEER"' ' || true
}

# ---- detect
: >"$TMP/plan"
n=0
while read -r t pinned; do
  [ -z "$ONLY" ] || [ "$t" = "$ONLY" ] || continue
  n=$((n + 1))
  latest="$("$UPSTREAM" --latest "$t" 2>/dev/null)"
  if [ -z "$latest" ]; then say "skip $t: upstream unreachable (pinned $pinned)"
  elif [ "$latest" = "$pinned" ]; then :
  elif [ "$t" = ffmpeg ] && ! ffmpeg_ready "$latest"; then say "skip ffmpeg: not every platform's build is $latest yet"
  else echo "$t $pinned $latest" >>"$TMP/plan"
  fi
done < <("$SYNC" --pins)

if [ "$n" = 0 ]; then say "no pinned tool named '$ONLY'"; exit 1; fi
if [ ! -s "$TMP/plan" ]; then say "nothing newer: $n tool(s) at upstream"; exit 0; fi
while read -r t old new; do say "plan $t $old -> $new"; done <"$TMP/plan"

# ---- baseline: doctor's FAIL set before any bump
if [ "$DRY" = 0 ]; then
  "$DOCTOR" >"$TMP/doctor.before" 2>&1
  gate_fails "$TMP/doctor.before" >"$TMP/gate.before"
fi

# ---- bump, then install
: >"$TMP/docpairs"
while read -r t old new; do
  bump_one "$t" "$old" "$new" || fail "$t $old -> $new: see the lines above"
  echo "$t $old $new" >>"$TMP/docpairs"
done <"$TMP/plan"

if [ "$DRY" = 1 ]; then
  say "dry run: $(wc -l <"$TMP/plan" | tr -d ' ') tool(s) would bump; nothing changed"
  exit 0
fi

while read -r t old new; do doc_rewrite "$t" "$old" "$new" || fail "docs/tools.md row for $t"; done <"$TMP/docpairs"

say "syncing tools"
if ! "$REALSYNC" >"$TMP/sync.out" 2>&1; then log_tail "$TMP/sync.out"; fail "sync-tools failed"; fi

# ---- gate: doctor must add no FAIL
"$DOCTOR" >"$TMP/doctor.after" 2>&1
gate_fails "$TMP/doctor.after" >"$TMP/gate.after"
new_fails="$(grep -vxFf "$TMP/gate.before" "$TMP/gate.after")"
if [ -n "$new_fails" ]; then
  printf '%s\n' "$new_fails" | while IFS= read -r l; do say "  new $l"; done
  fail "doctor reports a new FAIL after the bump"
fi

summary="$(awk '{printf "%s%s %s -> %s", (NR > 1 ? ", " : ""), $1, $2, $3}' "$TMP/plan")"
say "doctor: no new FAIL"

if [ "$NOCOMMIT" = 1 ]; then
  git --no-pager diff -- scripts docs
  say "no-commit: $(git diff --stat | tail -n 1); stopping before commit"
  restore_tree
  exit 0
fi

git add -- scripts/sync-tools.sh docs/tools.md
git commit -q -m "auto-update: $summary" || fail "git commit failed"
sha="$(git rev-parse --short HEAD)"
git push -q origin main || { say "push failed: commit $sha is local, push it by hand"; exit 1; }
say "committed and pushed $sha: $summary"

# ---- silence
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10)
if ! "${SSH[@]}" "$PEER" true >/dev/null 2>&1; then
  say "silence unreachable: it catches up on the next bump"
  exit 0
fi
if "${SSH[@]}" "$PEER" 'zsh -ic "cd ~/Developer/environment && git pull --ff-only -q && stow --no-folding -t \$HOME home && scripts/sync-tools.sh"' >"$TMP/silence.out" 2>&1; then
  say "silence: pulled, stowed and synced"
else
  say "silence: update failed:"; log_tail "$TMP/silence.out"
  exit 1
fi
