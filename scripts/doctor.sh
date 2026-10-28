#!/usr/bin/env bash
# doctor — read-only check that this machine matches the environment system.
# One line per check; exits nonzero if anything fails. Never prints secrets.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE_URL="https://ghost.tail483f5.ts.net:4096"   # update here if the tailnet is renamed
ROLE=silence
[ "$(scutil --get LocalHostName 2>/dev/null)" = ghost ] && ROLE=ghost
[ "$(uname -s)" = Linux ] && ROLE=box   # the box: the only Linux machine
PEER=ghost
[ "$ROLE" = ghost ] && PEER=silence
fails=0

check() { # check "description" command...
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$desc"
  else printf '  FAIL  %s\n' "$desc"; fails=$((fails + 1)); fi
}

# Password is read from a file or env var and passed to curl via stdin,
# so it never appears in argv, output, or shell history.
service_password() {
  if [ "$ROLE" = ghost ]; then
    python3 -c 'import json,os; print(json.load(open(os.path.expanduser("~/.config/opencode/service.json")))["password"])'
  else
    printf '%s' "${OPENCODE_SERVER_PASSWORD:-}"
  fi
}

http_code() { # http_code URL -> prints status code from an authenticated GET
  printf 'user = "opencode:%s"\n' "$(service_password)" \
    | curl -s -o /dev/null -w '%{http_code}' --max-time 8 -K - "$1"
}

echo "doctor ($ROLE) — $REPO"

echo "repo"
check "working tree clean" test -z "$(git -C "$REPO" status --porcelain)"
check "in sync with origin" test "$(git -C "$REPO" rev-parse HEAD)" = "$(git -C "$REPO" rev-parse '@{u}' 2>/dev/null)"
check "no obvious secret-named files tracked" test -z "$(git -C "$REPO" ls-files | grep -E '(^|/)(id_[^/]*|authorized_keys|known_hosts|service\.json|auth\.json)$|\.local$')"

echo "tools"
check "stow installed" command -v stow
check "Stow tree is settled (dry run has no pending links)" sh -c "cd '$REPO' && ! stow --no-folding -n -t \"\$HOME\" home 2>&1 | grep -v '^WARNING' | grep -q ."
check "core tools resolve in a non-interactive shell" zsh -c 'command -v stow && command -v nvim && command -v opencode && command -v pnpm && command -v bun && command -v node && command -v npm && command -v gh && command -v cloudflared && command -v claude'
check "tools match pinned versions" "$REPO/scripts/sync-tools.sh" --check

# Postgres is ghost-only and start-on-demand (one local app, no network).
# A stopped server is a valid state, so this reports instead of failing.
if [ "$ROLE" = ghost ]; then
  check "postgres binaries resolve" sh -c 'command -v psql && command -v pg_ctl && command -v initdb'
  if pg_ctl -D "$HOME/.local/var/postgres" status >/dev/null 2>&1; then
    echo "  info  postgres running (started on demand)"
  else
    echo "  info  postgres stopped — start on demand: pg_ctl -D ~/.local/var/postgres start"
  fi
fi

# Version parity with the other machine, for every direct-installed tool.
# opencode is exempt (it self-updates). postgres is ghost-only, so only
# ghost compares it. Parity is verified from silence: silence is SSH-client
# only (Remote Login off), so ghost can never ssh into it — the ghost-side
# checks skip by design, and doctor on silence does the real comparison
# against ghost. The box also compares against ghost over its own
# tailscaled; until it is logged in to the tailnet those lines skip.
echo "version sync (with $PEER)"
parity() { # parity "label" "version command" — the same command runs on both machines
  local label=$1 cmd=$2 local_ver remote_ver
  local_ver=$(eval "$cmd" 2>/dev/null) || { echo "  FAIL  $label: cannot read local version"; fails=$((fails+1)); return; }
  remote_ver=$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$PEER" "$cmd" 2>/dev/null) \
    || { echo "  skip  $label: $PEER unreachable"; return; }
  if [ "$local_ver" = "$remote_ver" ]; then
    echo "  ok    $label $local_ver (matches $PEER)"
  else
    echo "  FAIL  $label: local $local_ver, $PEER $remote_ver"
    fails=$((fails+1))
  fi
}
parity "stow"     'stow --version | awk "{print \$NF}"'
parity "nvim"     'nvim --version | head -1 | sed "s/^NVIM //"'
parity "pnpm"     'pnpm --version'
parity "bun"      'bun --version'
parity "node"     'node --version'
parity "gh"       'gh --version | head -1'
parity "cloudflared" 'cloudflared --version | head -1 | awk "{print \$3}"'
[ "$ROLE" != box ] && parity "claude"   'claude --version'   # box: native installer, own version
[ "$ROLE" = ghost ] && parity "postgres" 'postgres --version | awk "{print \$NF}"'

# Rex: each Mac's Rex is on the tailnet as node <mac>-rex (built-in
# Tailscale, see docs/workflows.md). Warn only: the node may be awaiting
# sign-in, and the app may not be running. Never starts a server and never
# prints the status (it can hold a sign-in link). Skipped on the box.
if [ "$ROLE" != box ]; then
  echo "rex"
  rex_node="$(scutil --get LocalHostName 2>/dev/null)-rex"
  if rex server status --autostart=false --timeout 5s 2>/dev/null | grep -q "tailscale: running · $rex_node\."; then
    echo "  ok    rex node $rex_node on the tailnet"
  else
    echo "  warn  rex node $rex_node not running (check: rex server status)"
  fi
fi

if [ "$ROLE" = silence ]; then
  echo "silence"
  check "ssh ghost works without a password" ssh -o BatchMode=yes -o ConnectTimeout=5 ghost true
  check "OpenCode service reachable over tailnet" test "$(http_code $SERVICE_URL/api/info)" = 200
  check "OPENCODE_SERVER_PASSWORD is set" test -n "${OPENCODE_SERVER_PASSWORD:-}"
fi

if [ "$ROLE" = box ]; then
  echo "box"
  check "\$HOME/.local/bin is first on PATH in zsh" zsh -c 'test "${PATH%%:*}" = "$HOME/.local/bin"'
  check "tools resolve from ~/.local/bin, not the system" zsh -c 'for t in stow nvim pnpm bun node npm gh cloudflared; do case "$(command -v $t)" in "$HOME/.local/bin/"*) ;; *) exit 1 ;; esac; done'
  check "ssh config parses (UseKeychain ignored via ~/.ssh/config.local)" ssh -G ghost
  check "claude resolves" command -v claude
  check "pstack plugin enabled in Claude Code" sh -c 'claude plugin list 2>/dev/null | grep -A3 "pstack@cursor-plugins" | grep -q enabled'
  check "tailscale installed" command -v tailscale
  # rex shim (home/.local/bin/rex) drives ghost's Rex over ssh; warn only.
  if ssh -o BatchMode=yes -o ConnectTimeout=6 ghost true 2>/dev/null; then
    check "rex ls over ssh ghost works" sh -c 'rex ls </dev/null >/dev/null 2>&1'
  else
    echo "  warn  rex over ssh: ghost unreachable"
  fi
  # No systemd on the box: tailscaled is started by ~/.local/bin/box-tailscaled
  # (machine-local). Not running / not logged in is reported, not failed.
  if ! tailscale status >/dev/null 2>&1; then
    if pgrep -x tailscaled >/dev/null; then
      echo "  info  tailscale not logged in — run: tailscale up --hostname=grokbox --accept-dns=false"
    else
      echo "  info  tailscaled not running — start it: box-tailscaled"
    fi
  fi
  if claude auth status 2>/dev/null | grep -q '"loggedIn": *false'; then
    echo "  info  claude not logged in — sign in, then run /pstack:setup-pstack"
  fi
fi

if [ "$ROLE" = ghost ]; then
  echo "ghost"
  check "launchd job ai.opencode.service loaded" sh -c 'launchctl list | grep -q ai.opencode.service'
  check "service listens on loopback only" sh -c 'lsof -nP -iTCP:4096 -sTCP:LISTEN | grep -q 127.0.0.1:4096'
  check "service answers with auth on loopback" test "$(http_code http://127.0.0.1:4096/api/info)" = 200
  check "tailscale serve proxies OpenCode" sh -c '/Applications/Tailscale.app/Contents/MacOS/Tailscale serve status | grep -q "proxy http://127.0.0.1:4096"'
  check "tailnet URL answers with auth" test "$(http_code $SERVICE_URL/api/info)" = 200
  check "upstream check job loaded (weekly report)" sh -c 'launchctl list | grep -q dev.scozu.check-upstream'
fi

echo
if [ "$fails" -eq 0 ]; then echo "all checks passed"; else echo "$fails check(s) failed"; fi
exit $((fails > 0))
