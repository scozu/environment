#!/usr/bin/env bash
# doctor — read-only check that this machine matches the environment system.
# One line per check; exits nonzero if anything fails. Never prints secrets.
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TAILNET="tail483f5.ts.net"   # update here if the tailnet is renamed
SERVICE_URL="https://ghost.${TAILNET}:4096"
GHOST_TS="ghost.${TAILNET}"
SILENCE_TS="silence.${TAILNET}"
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
check "Stow tree is settled (dry run has no pending links)" sh -c "cd '$REPO' && ! stow --no-folding -n -v -t \"\$HOME\" home 2>&1 | grep -v '^WARNING' | grep -q ."
check "core tools resolve in a non-interactive shell" zsh -c 'command -v stow && command -v nvim && command -v opencode && command -v pnpm && command -v bun && command -v node && command -v npm && command -v gh && command -v cloudflared && command -v claude && command -v ffmpeg && command -v ffprobe'
check "tools match pinned versions" "$REPO/scripts/sync-tools.sh" --check
check "ffmpeg is the pinned static build and encodes a frame" sh -c 'case "$(command -v ffmpeg)" in "$HOME/.local/bin/"*) ;; *) exit 1 ;; esac && ffmpeg -v error -f lavfi -i color=c=black:s=2x2 -frames:v 1 -f rawvideo -pix_fmt rgb24 - | wc -c | grep -qx " *12"'

# rustup is a sync-tools pin on macOS only (Linux assets are in the script
# but TOOLS skips it on the box, which may already have a system rustc).
# Skip cleanly on Linux, whether or not rustup is present there.
if [ "$(uname -s)" = Darwin ]; then
  check "rustup resolves from ~/.local/bin" sh -c 'case "$(command -v rustup)" in "$HOME/.local/bin/"*) ;; *) exit 1 ;; esac'
  check "RUSTUP_HOME and CARGO_HOME are ~/.local/opt/rustup/{rustup,cargo} in zsh" \
    zsh -c 'test "$RUSTUP_HOME" = "$HOME/.local/opt/rustup/rustup" && test "$CARGO_HOME" = "$HOME/.local/opt/rustup/cargo"'
  check "pdftotext resolves from ~/.local/bin" sh -c 'case "$(command -v pdftotext)" in "$HOME/.local/bin/"*) ;; *) exit 1 ;; esac'
fi

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
# against ghost. The box has no SSH to ghost (its shell egress is an HTTP
# proxy), so it skips parity here; compare with the ghost-env MCP server's
# `versions` tool instead (docs/workflows.md).
echo "version sync (with $PEER)"
if [ "$ROLE" = box ]; then
  echo "  skip  parity: the box has no ssh to ghost — use the ghost-env MCP versions tool"
else
# The peer is probed once. Each version command ends in a pipe (awk, sed,
# head), so its exit status says nothing about the tool: an empty version is
# treated as unreadable. Locally that fails; from the peer it skips (asleep,
# ssh dropped mid-run, or the tool isn't installed there).
peer_up=0
ssh -o BatchMode=yes -o ConnectTimeout=6 "$PEER" true >/dev/null 2>&1 && peer_up=1
parity() { # parity "label" "version command" — the same command runs on both machines
  local label=$1 cmd=$2 local_ver remote_ver
  local_ver=$(eval "$cmd" 2>/dev/null)
  if [ -z "$local_ver" ]; then
    echo "  FAIL  $label: cannot read local version"; fails=$((fails+1)); return
  fi
  if [ "$peer_up" != 1 ]; then
    echo "  skip  $label: $PEER unreachable"; return
  fi
  remote_ver=$(ssh -o BatchMode=yes -o ConnectTimeout=6 "$PEER" "$cmd" 2>/dev/null)
  if [ -z "$remote_ver" ]; then
    echo "  skip  $label: no version from $PEER (unreachable or not installed there)"; return
  fi
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
parity "ffmpeg"   'ffmpeg -version | head -1 | awk "{print \$3}"'
parity "claude"   'claude --version'   # the box never gets here (own native installer)
parity "rustup"   'rustup --version | head -1 | awk "{print \$2}"'
parity "cmake"    'cmake --version | head -1 | awk "{print \$3}"'
parity "pdftotext" 'pdftotext -v 2>&1 | head -1 | awk "{print \$3}"'
[ "$ROLE" = ghost ] && parity "postgres" 'postgres --version | awk "{print \$NF}"'
fi

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
  # The other Mac is added as a remote host in the app (see docs/workflows.md).
  # Hosts can't be read while the Rex server is down, so skip rather than warn.
  if ! rex server status --autostart=false --timeout 5s >/dev/null 2>&1; then
    echo "  skip  rex host $PEER: Rex server not running"
  elif rex hosts --json --autostart=false --timeout 5s 2>/dev/null | grep -q "\"label\": *\"$PEER\""; then
    echo "  ok    rex host $PEER saved"
  else
    echo "  warn  rex host $PEER missing — add it in Rex: Settings > Remote Hosts"
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
  check "tools resolve from ~/.local/bin, not the system" zsh -c 'for t in stow nvim pnpm bun node npm gh cloudflared ffmpeg ffprobe; do case "$(command -v $t)" in "$HOME/.local/bin/"*) ;; *) exit 1 ;; esac; done'
  check "ssh config parses (UseKeychain ignored via ~/.ssh/config.local)" ssh -G ghost
  check "~/.ssh is mode 700" sh -c 'test "$(stat -c %a "$HOME/.ssh" 2>/dev/null || stat -f %Lp "$HOME/.ssh" 2>/dev/null)" = 700'
  check "claude resolves" command -v claude
  check "pstack plugin enabled in Claude Code" sh -c 'claude plugin list 2>/dev/null | grep -A3 "pstack@cursor-plugins" | grep -q enabled'
  # Tailnet access comes from Grok Bot's Tailscale connector, not a local
  # tailscale/tailscaled, and the box's shell egress is an HTTP proxy: HTTPS
  # to a tailnet name works, SSH and raw TCP don't. So the ghost check is
  # envd's health endpoint behind ghost's tailnet-only serve on 443.
  if [ "$(curl -fsS -m 8 "https://$GHOST_TS/healthz" 2>/dev/null)" = ok ]; then
    echo "  ok    ghost-env reachable on the tailnet (https://$GHOST_TS/healthz)"
  else
    echo "  FAIL  ghost-env reachable on the tailnet (https://$GHOST_TS/healthz) — connect Tailscale in Grok Bot, or start envd on ghost (scripts/envd-setup.sh)"
    fails=$((fails + 1))
  fi
  # silence runs no envd. Any HTTPS response from its proofs port (a valid
  # ts.net certificate and an HTTP status) proves it is on the tailnet. It is
  # a laptop and may be asleep, so unreachable is a warning.
  code=$(curl -s -o /dev/null -w '%{http_code}' -m 8 "https://$SILENCE_TS:8443/" 2>/dev/null)
  if [ -n "$code" ] && [ "$code" != 000 ]; then
    echo "  ok    silence reachable on the tailnet (https://$SILENCE_TS:8443, HTTP $code)"
  else
    echo "  warn  silence unreachable on the tailnet (https://$SILENCE_TS:8443) — laptop may be asleep"
  fi
  # The rex shim (home/.local/bin/rex) drives ghost's Rex over ssh, which the
  # box can't do, so this is information only.
  echo "  info  rex shim needs ssh ghost, which the box doesn't have; the box uses the ghost-env MCP server"
  if claude auth status 2>/dev/null | grep -q '"loggedIn": *false'; then
    echo "  info  claude not logged in — sign in. Don't run /pstack:setup-pstack casually: it overwrites the tracked rule file; if it runs, git restore home/.claude/rules/pstack-models.md"
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
  check "proofs web LaunchAgent loaded" launchctl list com.studiopendleton.proofs-web
  check "envd LaunchAgent dev.scozu.envd loaded" launchctl list dev.scozu.envd
  check "envd answers on loopback (127.0.0.1:8790/healthz)" sh -c 'test "$(curl -fsS -m 5 http://127.0.0.1:8790/healthz)" = ok'
  check "envd listens on loopback only" sh -c '! lsof -nP -iTCP:8790 -sTCP:LISTEN | awk "NR>1{print \$9}" | grep -qv "^127\.0\.0\.1:8790\$"'
  check "tailscale serve proxies envd on 443 to 8790 (tailnet only)" sh -c '/Applications/Tailscale.app/Contents/MacOS/Tailscale serve status | awk -v h="https://'"$GHOST_TS"' (tailnet only)" "\$0==h{f=1;next} /^https?:/{f=0} f && / proxy http:\/\/127\.0\.0\.1:8790\$/{ok=1} END{exit !ok}"'
  check "ghost-env answers over the tailnet (https://$GHOST_TS/healthz)" sh -c 'test "$(curl -fsS -m 8 https://'"$GHOST_TS"'/healthz)" = ok'
  check "tailscale serve proxies proofs on 8443 to 8787 (tailnet only)" sh -c '/Applications/Tailscale.app/Contents/MacOS/Tailscale serve status | awk "/:8443 \(tailnet only\)/{f=1;next} /^https/{f=0} f && / proxy http:\/\/127\.0\.0\.1:8787\$/{ok=1} END{exit !ok}"'
fi

echo
if [ "$fails" -eq 0 ]; then echo "all checks passed"; else echo "$fails check(s) failed"; fi
exit $((fails > 0))
