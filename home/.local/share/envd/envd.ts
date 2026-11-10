// envd — "ghost-env" MCP server for the environment repo. Runs on ghost only
// (LaunchAgent dev.scozu.envd, set up by scripts/envd-setup.sh), listens on
// 127.0.0.1:8790, and is reached from the tailnet through
// `tailscale serve --https=443` (tailnet only, never Funnel).
//
// Transport: MCP Streamable HTTP, JSON responses only (no SSE), stateless.
//   POST /mcp      JSON-RPC 2.0: initialize, ping, tools/list, tools/call
//   GET  /healthz  200 "ok", no auth (doctor uses it)
//
// Tools run fixed argv lists with a timeout. Inputs are never passed to a
// shell or to a command line; no tool takes arguments.
//
// Auth: every /mcp request must arrive via tailscale serve (loopback peer, a
// single X-Forwarded-For address in the tailnet ranges), and that source must
// pass `tailscale whois`: an untagged node owned by an allowed login, a node
// with an allowed tag, or a tagged node whose hostname has an allowed prefix.
// Anything else, including whois failing, gets 403.
//
// Config: env vars, optionally from ~/.config/envd/env.local (KEY=VALUE
// lines, machine-local). See docs/workflows.md.

import { existsSync, readFileSync } from "node:fs";
import { homedir, platform } from "node:os";
import { join } from "node:path";

const VERSION = "1.0.0";
const HOME = homedir();

// ---------------------------------------------------------------- config
function loadEnvFile(path: string): Record<string, string> {
  const out: Record<string, string> = {};
  if (!existsSync(path)) return out;
  for (const raw of readFileSync(path, "utf8").split("\n")) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const m = line.match(/^(?:export\s+)?([A-Z0-9_]+)=(.*)$/);
    if (!m) continue;
    let v = m[2].trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
    out[m[1]] = v;
  }
  return out;
}
const fileEnv = loadEnvFile(join(HOME, ".config/envd/env.local"));
const cfg = (k: string, d: string) => process.env[k] ?? fileEnv[k] ?? d;
const list = (s: string) => s.split(",").map((x) => x.trim()).filter(Boolean);

const PORT = Number(cfg("ENVD_PORT", "8790"));
const REPO = cfg("ENVD_REPO", join(HOME, "Developer/environment"));
const ALLOW_LOGINS = list(cfg("ENVD_ALLOW_LOGINS", "admin@jasonscholtz.net")).map((s) => s.toLowerCase());
const ALLOW_TAGS = list(cfg("ENVD_ALLOW_TAGS", "tag:grokbot"));
const ALLOW_HOST_PREFIXES = list(cfg("ENVD_ALLOW_HOST_PREFIXES", "grokbot-")).map((s) => s.toLowerCase());
const TAILSCALE = cfg("ENVD_TAILSCALE", "/Applications/Tailscale.app/Contents/MacOS/Tailscale");
const TIMEOUT_MS = Number(cfg("ENVD_TIMEOUT_S", "120")) * 1000;
// Local testing only: skips the serve/whois checks. Refused on macOS so it
// can never be left on in ghost's LaunchAgent; only read from the process env.
const TEST_BYPASS = process.env.ENVD_INSECURE_LOCAL_TEST === "1";
if (TEST_BYPASS && platform() === "darwin") {
  console.error("envd: ENVD_INSECURE_LOCAL_TEST is refused on macOS");
  process.exit(2);
}

const PATH = [join(HOME, ".local/bin"), join(HOME, ".opencode/bin"), "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"].join(":");
const MAX_OUTPUT = 200_000;
const MAX_BODY = 1_000_000;
const PROTOCOLS = ["2025-11-25", "2025-06-18", "2025-03-26"];

const log = (...a: unknown[]) => console.log(new Date().toISOString(), ...a);

// ---------------------------------------------------------------- exec
type RunResult = { argv: string[]; code: number | null; timedOut: boolean; timeoutMs: number; out: string };

async function drain(stream: ReadableStream<Uint8Array>, sink: { s: string }) {
  const dec = new TextDecoder();
  for await (const chunk of stream) {
    if (sink.s.length < MAX_OUTPUT) sink.s += dec.decode(chunk, { stream: true });
  }
}

// Fixed argv, no shell. On timeout the child is killed; if a grandchild still
// holds the pipes, the output so far is returned after a short grace period.
async function run(argv: string[], timeoutMs = TIMEOUT_MS): Promise<RunResult> {
  let proc: ReturnType<typeof Bun.spawn>;
  try {
    proc = Bun.spawn(argv, {
      cwd: REPO,
      env: { HOME, PATH, LANG: "en_US.UTF-8", USER: process.env.USER ?? "", LOGNAME: process.env.LOGNAME ?? "", TERM: "dumb", GIT_TERMINAL_PROMPT: "0" },
      stdin: "ignore",
      stdout: "pipe",
      stderr: "pipe",
    });
  } catch (e) {
    return { argv, code: 127, timedOut: false, timeoutMs, out: `cannot start ${argv[0]}: ${(e as Error).message}\n` };
  }
  const o = { s: "" }, e = { s: "" };
  const done = Promise.all([drain(proc.stdout as ReadableStream<Uint8Array>, o), drain(proc.stderr as ReadableStream<Uint8Array>, e), proc.exited]);
  let timer: ReturnType<typeof setTimeout> | undefined;
  const expired = new Promise<"timeout">((r) => { timer = setTimeout(() => r("timeout"), timeoutMs); });
  const timedOut = (await Promise.race([done, expired])) === "timeout";
  clearTimeout(timer);
  if (timedOut) {
    proc.kill("SIGKILL");
    await Promise.race([done, Bun.sleep(2000)]);
  }
  let out = o.s + (e.s ? (o.s && !o.s.endsWith("\n") ? "\n" : "") + e.s : "");
  if (out.length > MAX_OUTPUT) out = out.slice(0, MAX_OUTPUT) + "\n… (output truncated)";
  return { argv, code: timedOut ? null : proc.exitCode, timedOut, timeoutMs, out };
}

function fmt(r: RunResult): string {
  const status = r.timedOut ? `timed out after ${r.timeoutMs / 1000}s` : `exit ${r.code}`;
  return `$ ${r.argv.join(" ")}\n${r.out}${r.out.endsWith("\n") || !r.out ? "" : "\n"}[${status}]`;
}

// One tool run at a time: doctor, pull and stow all read the same tree.
let chain: Promise<unknown> = Promise.resolve();
function serial<T>(fn: () => Promise<T>): Promise<T> {
  const p = chain.then(fn, fn);
  chain = p.catch(() => {});
  return p;
}

// ---------------------------------------------------------------- tools
type ToolOut = { text: string; isError: boolean };
type Tool = { description: string; handler: () => Promise<ToolOut> };

const one = async (argv: string[]): Promise<ToolOut> => {
  const r = await run(argv);
  return { text: fmt(r), isError: r.code !== 0 };
};

const TOOLS: Record<string, Tool> = {
  doctor: {
    description: "Run scripts/doctor.sh in ~/Developer/environment on ghost; returns its output and exit code.",
    handler: () => one(["/bin/bash", join(REPO, "scripts/doctor.sh")]),
  },
  versions: {
    description: "Pinned versions (scripts/sync-tools.sh --pins) next to installed versions (sync-tools.sh --check) on ghost.",
    handler: async () => {
      const pins = await run(["/bin/bash", join(REPO, "scripts/sync-tools.sh"), "--pins"]);
      const check = await run(["/bin/bash", join(REPO, "scripts/sync-tools.sh"), "--check"]);
      return { text: `${fmt(pins)}\n\n${fmt(check)}`, isError: pins.code !== 0 || check.code !== 0 };
    },
  },
  repo_status: {
    description: "git status -sb and git log -1 for ~/Developer/environment on ghost.",
    handler: async () => {
      const s = await run(["git", "-C", REPO, "status", "-sb"]);
      const l = await run(["git", "-C", REPO, "log", "-1", "--format=%H%n%an <%ae>%n%aI%n%s"]);
      return { text: `${fmt(s)}\n\n${fmt(l)}`, isError: s.code !== 0 || l.code !== 0 };
    },
  },
  repo_pull: {
    description: "git pull --ff-only in ~/Developer/environment on ghost. Refuses unless on main with a clean working tree.",
    handler: async () => {
      const b = await run(["git", "-C", REPO, "symbolic-ref", "--short", "HEAD"]);
      if (b.code !== 0 || b.out.trim() !== "main") return { text: `refused: not on main\n\n${fmt(b)}`, isError: true };
      const d = await run(["git", "-C", REPO, "status", "--porcelain"]);
      if (d.code !== 0 || d.out.trim() !== "") return { text: `refused: working tree is dirty\n\n${fmt(d)}`, isError: true };
      return one(["git", "-C", REPO, "pull", "--ff-only"]);
    },
  },
  stow_dry_run: {
    description: "stow -n -v --no-folding -t $HOME home in ~/Developer/environment on ghost (dry run, changes nothing).",
    handler: () => one(["stow", "-n", "-v", "--no-folding", "-d", REPO, "-t", HOME, "home"]),
  },
  sync_tools_check: {
    description: "scripts/sync-tools.sh --check on ghost (read-only; exit 1 if any tool differs from its pin).",
    handler: () => one(["/bin/bash", join(REPO, "scripts/sync-tools.sh"), "--check"]),
  },
};

// ---------------------------------------------------------------- auth
function isTailnetIP(ip: string): boolean {
  const v4 = ip.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (v4) { const a = +v4[1], b = +v4[2]; return a === 100 && b >= 64 && b <= 127; } // 100.64.0.0/10
  return /^fd7a:115c:a1e0:/i.test(ip); // fd7a:115c:a1e0::/48
}
const isLoopback = (ip: string) => ip === "127.0.0.1" || ip === "::1" || ip === "::ffff:127.0.0.1";

type Decision = { ok: boolean; who: string };
const whoisCache = new Map<string, { at: number; d: Decision }>();

async function whois(ip: string): Promise<Decision> {
  const hit = whoisCache.get(ip);
  if (hit && Date.now() - hit.at < 60_000) return hit.d;
  let d: Decision = { ok: false, who: `${ip} (whois failed)` };
  if (existsSync(TAILSCALE)) {
    const r = await run([TAILSCALE, "whois", "--json", ip], 10_000);
    if (r.code === 0) {
      try {
        const j = JSON.parse(r.out);
        const tags: string[] = j?.Node?.Tags ?? [];
        const login = String(j?.UserProfile?.LoginName ?? "").toLowerCase();
        const names = [j?.Node?.Hostinfo?.Hostname, j?.Node?.ComputedName, String(j?.Node?.Name ?? "").split(".")[0]]
          .filter(Boolean).map((s: string) => s.toLowerCase());
        const who = `${names[0] ?? "?"} ${tags.length ? tags.join(",") : login} ${ip}`;
        const ok =
          (tags.length === 0 && ALLOW_LOGINS.includes(login)) ||
          tags.some((t) => ALLOW_TAGS.includes(t)) ||
          (tags.length > 0 && names.some((n) => ALLOW_HOST_PREFIXES.some((p) => n.startsWith(p))));
        d = { ok, who };
      } catch { /* deny */ }
    }
  }
  whoisCache.set(ip, { at: Date.now(), d });
  return d;
}

async function authorize(req: Request, peer: string): Promise<Decision> {
  if (TEST_BYPASS) return { ok: true, who: "local test bypass" };
  if (!isLoopback(peer)) return { ok: false, who: `${peer} (not loopback)` };
  const xff = (req.headers.get("x-forwarded-for") ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  if (xff.length !== 1 || !isTailnetIP(xff[0])) return { ok: false, who: `${peer} (not via tailscale serve)` };
  return whois(xff[0]);
}

// ---------------------------------------------------------------- JSON-RPC
type Rpc = { jsonrpc?: string; id?: string | number | null; method?: string; params?: any };
const ok = (id: Rpc["id"], result: unknown) => ({ jsonrpc: "2.0", id, result });
const err = (id: Rpc["id"], code: number, message: string) => ({ jsonrpc: "2.0", id: id ?? null, error: { code, message } });

async function handle(msg: Rpc, who: string): Promise<object | null> {
  if (!msg || typeof msg !== "object" || msg.jsonrpc !== "2.0" || typeof msg.method !== "string")
    return err(msg?.id ?? null, -32600, "invalid request");
  const isNotification = !("id" in msg);
  if (isNotification) return null; // notifications/initialized, cancelled, …
  const { id, method, params } = msg;
  switch (method) {
    case "initialize": {
      const asked = params?.protocolVersion;
      return ok(id, {
        protocolVersion: PROTOCOLS.includes(asked) ? asked : PROTOCOLS[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: "ghost-env", version: VERSION },
        instructions: "Read-only checks and a fast-forward pull for ~/Developer/environment on ghost. No arbitrary commands.",
      });
    }
    case "ping":
      return ok(id, {});
    case "tools/list":
      return ok(id, {
        tools: Object.entries(TOOLS).map(([name, t]) => ({
          name,
          description: t.description,
          inputSchema: { type: "object", properties: {}, additionalProperties: false },
          annotations: { readOnlyHint: name !== "repo_pull", destructiveHint: false, idempotentHint: true, openWorldHint: false },
        })),
      });
    case "tools/call": {
      const name = params?.name;
      const tool = typeof name === "string" && Object.hasOwn(TOOLS, name) ? TOOLS[name] : undefined;
      if (!tool) return err(id, -32602, `unknown tool: ${String(name)}`);
      const args = params?.arguments;
      if (args !== undefined && (typeof args !== "object" || args === null || Object.keys(args).length > 0))
        return err(id, -32602, `${name} takes no arguments`);
      log("call", name, "by", who);
      const r = await serial(tool.handler).catch((e) => ({ text: `envd error: ${(e as Error).message}`, isError: true }));
      log("done", name, r.isError ? "error" : "ok");
      return ok(id, { content: [{ type: "text", text: r.text }], isError: r.isError });
    }
    default:
      return err(id, -32601, `method not found: ${method}`);
  }
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

const server = Bun.serve({
  hostname: "127.0.0.1",
  port: PORT,
  idleTimeout: 0, // tool calls (doctor) can run up to the tool timeout
  error(e) {
    log("error", e.message);
    return json(err(null, -32603, "internal error"), 500);
  },
  async fetch(req, srv) {
    const url = new URL(req.url);
    if (url.pathname === "/healthz") {
      return req.method === "GET" || req.method === "HEAD" ? new Response("ok\n") : new Response("method not allowed\n", { status: 405 });
    }
    if (url.pathname !== "/mcp") return new Response("not found\n", { status: 404 });

    const peer = srv.requestIP(req)?.address ?? "";
    const a = await authorize(req, peer);
    if (!a.ok) {
      log("deny", req.method, url.pathname, a.who);
      return new Response("forbidden\n", { status: 403 });
    }
    if (req.method === "DELETE") return new Response(null, { status: 405 }); // stateless: no sessions to end
    if (req.method !== "POST") return new Response("method not allowed\n", { status: 405, headers: { allow: "POST" } });

    const len = Number(req.headers.get("content-length") ?? "0");
    if (len > MAX_BODY) return json(err(null, -32600, "request too large"), 413);
    let body: unknown;
    try {
      const text = await req.text();
      if (text.length > MAX_BODY) return json(err(null, -32600, "request too large"), 413);
      body = JSON.parse(text);
    } catch {
      return json(err(null, -32700, "parse error"), 400);
    }

    if (Array.isArray(body)) { // legacy batch support
      const out = (await Promise.all(body.map((m) => handle(m as Rpc, a.who)))).filter(Boolean);
      return out.length ? json(out) : new Response(null, { status: 202 });
    }
    const out = await handle(body as Rpc, a.who);
    return out ? json(out) : new Response(null, { status: 202 });
  },
});

log(`envd ${VERSION} (ghost-env) on http://${server.hostname}:${server.port} repo=${REPO}${TEST_BYPASS ? " AUTH BYPASSED (local test)" : ""}`);
