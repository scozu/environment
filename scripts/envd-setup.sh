#!/usr/bin/env bash
# envd-setup — install and start envd (the ghost-env MCP server) on ghost, and
# publish it on the tailnet at https://ghost.tail483f5.ts.net/ (443, tailnet
# only). Idempotent: safe to re-run after every pull.
#
#   1. render launchd/dev.scozu.envd.plist into ~/Library/LaunchAgents
#   2. bootstrap the LaunchAgent, or kickstart it if already loaded
#   3. wait for http://127.0.0.1:8790/healthz
#   4. add the 443 serve mapping if missing. Never touches other serve ports
#      (4096 OpenCode, 8443 proofs) and refuses if 443 already serves
#      something else.
#   5. print `tailscale serve status`
#
# Prereqs: `stow --no-folding -t "$HOME" home` has linked ~/.local/bin/envd
# and ~/.local/share/envd/envd.ts, and bun is on ~/.local/bin.
set -euo pipefail

LABEL=dev.scozu.envd
PORT=8790
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TS=/Applications/Tailscale.app/Contents/MacOS/Tailscale
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
die() { echo "envd-setup: $*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "macOS only (envd runs on ghost)"
[ "$(scutil --get LocalHostName 2>/dev/null)" = ghost ] || die "ghost only (silence runs no tool launchd jobs)"
[ -x "$TS" ] || die "tailscale CLI not found at $TS"
[ -x "$HOME/.local/bin/bun" ] || die "bun not found at ~/.local/bin/bun (scripts/sync-tools.sh)"
[ -e "$HOME/.local/bin/envd" ] && [ -e "$HOME/.local/share/envd/envd.ts" ] \
  || die "envd not stowed yet: cd $REPO && stow --no-folding -t \"\$HOME\" home"

# Port 8790 must be free or already ours.
holder=$(lsof -nP -iTCP:$PORT -sTCP:LISTEN -t 2>/dev/null | head -1 || true)
if [ -n "$holder" ] && ! launchctl print "$DOMAIN/$LABEL" 2>/dev/null | grep -q "pid = $holder\$"; then
  die "port $PORT is held by pid $holder, not $LABEL"
fi

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.local/var" "$HOME/.config/envd"
tmp=$(mktemp)
sed "s|@HOME@|$HOME|g" "$REPO/launchd/$LABEL.plist" >"$tmp"
plutil -lint "$tmp" >/dev/null || die "rendered plist failed plutil -lint"
changed=0
if ! cmp -s "$tmp" "$PLIST" 2>/dev/null; then
  install -m 644 "$tmp" "$PLIST"; changed=1; echo "installed $PLIST"
fi
rm -f "$tmp"

if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
  if [ "$changed" = 1 ]; then
    launchctl bootout "$DOMAIN/$LABEL" || true
    sleep 1
    launchctl bootstrap "$DOMAIN" "$PLIST"; echo "reloaded $LABEL"
  else
    launchctl kickstart -k "$DOMAIN/$LABEL"; echo "restarted $LABEL"
  fi
else
  launchctl bootstrap "$DOMAIN" "$PLIST"; echo "loaded $LABEL"
fi

for _ in $(seq 1 20); do
  curl -fsS -m 2 "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1 && break
  sleep 0.5
done
curl -fsS -m 2 "http://127.0.0.1:$PORT/healthz" >/dev/null \
  || die "envd did not answer on 127.0.0.1:$PORT — see ~/.local/var/envd.log"
echo "envd healthy on 127.0.0.1:$PORT"

# 443 block in `serve status`: the header line without a port, up to the next header.
host=$("$TS" status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')
block=$("$TS" serve status 2>/dev/null | awk -v h="https://$host " 'index($0,h)==1{f=1;print;next} /^https?:\/\//{f=0} f')
if [ -z "$block" ]; then
  "$TS" serve --bg --https=443 "http://127.0.0.1:$PORT"
  echo "added serve https://$host/ -> 127.0.0.1:$PORT"
elif printf '%s\n' "$block" | grep -q "proxy http://127.0.0.1:$PORT\$" && printf '%s\n' "$block" | grep -q '(tailnet only)'; then
  echo "serve 443 already -> 127.0.0.1:$PORT (tailnet only)"
else
  printf '%s\n' "$block" >&2
  die "443 already serves something else; not changing it (fix by hand: tailscale serve status)"
fi

echo
"$TS" serve status
