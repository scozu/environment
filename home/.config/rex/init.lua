-- Rex configuration, stowed on every machine. Each Mac's own Rex server
-- reads it (it lives with the server, per the Rex docs).
--
-- Every Mac is both a Rex client and a Rex server. Each Mac's Rex joins the
-- tailnet as its own node `<mac>-rex` (built-in Tailscale, owner-only access;
-- see docs/workflows.md). Each Mac declares every other Mac as a remote host,
-- labeled by the Mac's name, so `rex -S ghost ...` / `rex -S silence ...`
-- and the app's host list reach the other Mac's sessions. A Mac skips itself.
-- Check: `rex config check`; apply: `rex config reload` (on that machine).

local hosts = {
  ghost = "https://ghost-rex.tail483f5.ts.net",
  silence = "https://silence-rex.tail483f5.ts.net",
}

local r = rex.exec({ "/usr/sbin/scutil", "--get", "LocalHostName" })
local me = (r and r.ok and r.stdout or ""):gsub("%s+$", "")

for _, label in ipairs({ "ghost", "silence" }) do
  if label ~= me then
    rex.host{ id = label, label = label, endpoints = { hosts[label] } }
  end
end
