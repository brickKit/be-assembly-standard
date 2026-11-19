# Mutation check of infra/bff-mobile 3.0.0 (C11 P4): each mutation must turn a test red.
# Run from the component directory: PYTHONDONTWRITEBYTECODE=1 python3 <this file>
import subprocess, sys
M = [
 ("no forwarded credential", "internal/core/base.go", 'ForwardUser: true}', 'ForwardUser: false}'),
 ("mine not filtered", "internal/reads/sales.go", 'page(cursor, limit, "owner_id", me, "state"', 'page(cursor, limit, "owner_id", "", "state"'),
 ("entry operation skipped", "internal/entry/entry.go", 'if _, _, err := s.Check(ctx, core.OpEntry, authz.Facts{}); err != nil {', 'if _, _, err := s.Check(ctx, core.OpEntry, authz.Facts{}); err != nil && false {'),
 ("owner detail passed", "internal/entry/errors.go", 'title := own.Title', 'title := own.Title + own.Detail'),
 ("introspection allowed", "internal/queries/queries.go", 'w.introspection = true', 'w.introspection = false'),
 ("stock costs as an object", "internal/core/names.go", '"ProductDetail.stock": Inventory,', ''),
 ("absent owner not pruned", "internal/queries/queries.go", 'if present(owner) {', 'if true {'),
 ("catalog read every time", "internal/reads/stock.go", 'req, _ := ctx.Value(requestKey{}).(*request)', 'req := (*request)(nil)'),
 ("runtime limit not checked", "internal/entry/entry.go", 'if v := e.list.Limits(pq.SHA256Hash, op.Variables); len(v) > 0 {', 'if v := e.list.Limits(pq.SHA256Hash, op.Variables); len(v) > 99 {'),
 ("no retry_after", "internal/entry/errors.go", 'if s := retryAfter(own); s > 0 {', 'if s := retryAfter(own); s > 99 {'),
 ("dependency not named", "internal/core/base.go", 'e = e.With("dependency", owner)', 'e = e'),
 ("catalog warning dropped", "internal/graph/schema.resolvers.go", 'graphql.AddError(ctx, warning)', '_ = warning'),
 ("hash not checked", "internal/queries/queries.go", 'hex.EncodeToString(sum[:]) != hash {', 'hex.EncodeToString(sum[:]) == "" {'),
]
survived = []
for name, f, old, new in M:
    src = open(f).read()
    assert src.count(old) == 1, (name, src.count(old))
    open(f, "w").write(src.replace(old, new))
    try:
        r = subprocess.run("go vet ./... >/dev/null 2>&1; go test -count=1 ./... >/dev/null 2>&1 && go test -count=1 -tags integration ./itest/ >/dev/null 2>&1",
                           shell=True)
        killed = r.returncode != 0
    finally:
        open(f, "w").write(src)
    print(("KILLED  " if killed else "SURVIVED") + "  " + name, flush=True)
    if not killed:
        survived.append(name)
print("MUTATION DONE survived=%d of %d" % (len(survived), len(M)), flush=True)
sys.exit(1 if survived else 0)
