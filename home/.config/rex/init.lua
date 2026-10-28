-- Rex configuration, stowed on every machine. Each Mac's own Rex server
-- reads it (it lives with the server, per the Rex docs).
--
-- ghost's Rex is the session master and is on the tailnet as node `rex`
-- (built-in Tailscale). Every other machine declares it as a remote host,
-- so silence's app and `rex -S rex ...` reach ghost's sessions.
-- ghost skips the declaration so it never lists itself.
-- Check: `rex config check`; apply: `rex config reload` (on that machine).

local name = rex.exec({ "/usr/sbin/scutil", "--get", "LocalHostName" })
local on_ghost = name and name.ok and name.stdout:match("^ghost%s*$") ~= nil

if not on_ghost then
  rex.host{
    label = "rex",
    endpoints = { "https://rex.tail483f5.ts.net" },
  }
end
