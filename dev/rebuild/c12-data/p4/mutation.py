import subprocess, sys
M = [
 ("packages/shell/src/request.ts", 'const retriable = method === "GET" || Boolean(o.idempotencyKey);', 'const retriable = true;'),
 ("packages/shell/src/errors.ts", '  return { kind: "unknown", status, reason };', '  return { kind: "ok", status, body: problem };'),
 ("packages/shell/src/access.ts", 'const items = m.menu.filter((i) => permissions.has(i.operation));', 'const items = m.menu;'),
 ("packages/shell/src/access.ts", 'if (![m.component, ...m.needs].every((c) => has(features, c))) return false;', 'if (!has(features, m.component)) return false;'),
 ("packages/shell/src/drafts.ts", 'for (const f of allowed.fields) if (f in values) kept[f] = values[f];', 'Object.assign(kept, values);'),
 ("packages/shell/src/drafts.ts", 'if (d.state === "local") await this.store.delete(d.key);', 'await this.store.delete(d.key);'),
 ("packages/shell/src/drafts.ts", 'if (d.key.entry !== ENTRY || d.key.user !== this.user) continue;', 'if (d.key.entry !== ENTRY) continue;'),
 ("packages/shell/src/access.ts", 'this.stale = true; // keep the last keys', 'this.keys = new Set();'),
 ("packages/shell/src/access.ts", 'if (t - this.last403 < AFTER_403_MS) return;', ''),
 ("packages/build/src/compose.ts", 'const missing = [d.component, ...(d.needs ?? [])]', 'const missing = [d.component]'),
 ("packages/ui-kit-pc/src/export.ts", 'const formula = /^[=+\\-@\\t\\r]/;', 'const formula = /^[=+\\-]/;'),
 ("packages/ui-kit-pc/src/richtext.ts", 'if (!DOMPurify.isSupported) return escape(html);', ''),
 ("packages/shell/src/session.ts", 'path !== LOGGED_OUT ? path + search : "/"', 'true ? path + search : "/"'),
 ("packages/shell/src/request.ts", 'if (method !== "GET" && method !== "HEAD") headers["BE-Request"] = "1";', ''),
 ("packages/shell/src/runtime.ts", 'logoUrl: str("logoUrl")?.startsWith("/") ? str("logoUrl") : undefined,', 'logoUrl: str("logoUrl"),'),
]
bad = 0
for f, a, b in M:
    s = open(f).read()
    assert s.count(a) == 1, (f, a)
    open(f, "w").write(s.replace(a, b))
    r = subprocess.run(["npx", "vitest", "run"], capture_output=True, text=True)
    open(f, "w").write(s)
    ok = r.returncode != 0
    bad += not ok
    print(("killed  " if ok else "SURVIVED") + f"  {f}: {a[:60]}")
print("survivors:", bad)
