# Tailnet policy — proposed lockdown for the box (NOT applied)

Status: **proposal**. Nothing here is applied until Jason pastes it into the
Tailscale admin console (Access controls → policy file). The live policy
lives only in the admin console, never in this repo.

## Goal

The box (grokbox) reaches the tailnet through Grok Bot's Tailscale
connector. Its tailnet device should reach exactly one thing: envd, the
ghost-env MCP server, at `ghost:443`. Everything else on the tailnet
keeps working the way the default allow-all policy works today.

- Device to tag: **`grokbot-user-158631703`** (`100.121.13.52`), the
  connector's device. Admin console → Machines → that device → Edit ACL
  tags → `tag:grokbot`. (Uncertain: if the connector re-registers its
  device, the tag may need re-applying; envd also accepts a tagged device
  whose hostname starts with `grokbot-`.)
- Stale device to remove: **`grokbox`** (`100.127.67.48`), left offline by
  the old local tailscaled on the box. Admin console → Machines → Remove.
- ghost is untagged, so the policy names it with a host alias
  (`100.69.59.88`).

## Snippet

Merge these keys into the existing policy file. Replace the default
`{"src": ["*"], "dst": ["*"], "ip": ["*"]}` grant (or the legacy
`acls` accept-all rule) with the `autogroup:member` grant below: as long
as a `"src": ["*"]` rule exists, `tag:grokbot` matches it and the
lockdown means nothing. Keep any other grants you already have, such as
the proofs share (`autogroup:shared` → ghost `tcp:8443`), and the `ssh`
section.

```hujson
{
  "tagOwners": {
    // Only tailnet admins (Jason) can apply tag:grokbot.
    "tag:grokbot": ["autogroup:admin"],
  },

  "hosts": {
    "ghost": "100.69.59.88",
  },

  "grants": [
    // Your own (untagged, member-owned) devices: full access, like the
    // default allow-all today. Tagged devices are not autogroup:member,
    // so this does not cover tag:grokbot.
    {"src": ["autogroup:member"], "dst": ["*"], "ip": ["*"]},

    // The box (Grok Bot's connector device): ghost-env MCP on ghost only.
    {"src": ["tag:grokbot"], "dst": ["ghost"], "ip": ["tcp:443"]},
  ],

  "tests": [
    {
      "src":    "tag:grokbot",
      "accept": ["ghost:443"],
      "deny":   ["ghost:22", "ghost:8443", "ghost:4096"],
    },
  ],
}
```

## What changes for the box

- Works: `https://ghost.tail483f5.ts.net/mcp` and `/healthz` (envd).
- Stops working: the OpenCode service (`ghost:4096`, `opencode run
  --server …` from the box), proofs (`ghost:8443`), silence entirely, and
  anything else. Doctor on the box will then always warn for silence,
  which is expected. If the box should keep OpenCode, add `tcp:4096` to
  the tag:grokbot grant and move `ghost:4096` from `deny` to `accept` in
  the test.
- Other tagged devices, if any exist, also lose the access they got from
  `"src": ["*"]`. Check Machines for tags before applying.

## After applying

From the box, in a turn Jason starts:

```sh
curl -fsS -m 8 https://ghost.tail483f5.ts.net/healthz   # ok
curl -s -o /dev/null -w '%{http_code}\n' -m 8 https://ghost.tail483f5.ts.net:8443/   # 000 (denied)
scripts/doctor.sh
```
