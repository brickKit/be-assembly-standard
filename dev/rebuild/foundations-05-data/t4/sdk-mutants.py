TITLE = "be-sdk-go tiering (T4): declarations, the canonical row, the plan, sealing and the write barrier"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -tags integration ./tiering/"]
MUTANTS = [
    ("tiering/barrier.go", "    IF st IS NOT NULL AND st <> 'open' THEN", "    IF st IS NOT NULL AND st = 'destroyed' THEN", "the barrier refuses every state but open"),
    ("tiering/barrier.go", "    IF kind = 'child' THEN\n      EXECUTE", "    IF kind = 'none' THEN\n      EXECUTE", "a child's write locks its root first"),
    ("tiering/barrier.go", "      CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) ->> col END,", "      NULL,", "the old row's root counts too"),
    ("tiering/catalog.go", " LIMIT $%d FOR UPDATE OF r\",", " LIMIT $%d\",", "the seal locks the roots it seals (TR03)"),
    ("tiering/catalog.go", "\tfor _, r := range pending {\n\t\tout[r] = append(out[r], WhyEventsPending)\n\t}", "\t_ = pending", "unpublished events block"),
    ("tiering/catalog.go", "\t\t\tfor r, reasons := range why {\n\t\t\t\tout[r] = append(out[r], reasons...)\n\t\t\t}", "\t\t\t_ = why", "the module's blockers block"),
    ("tiering/catalog.go", "(%s) AND r.%s <= now() - make_interval(days => $1)", "(%s) AND r.%s <= now() + make_interval(days => $1)", "only past the residence (TR28)"),
    ("tiering/class.go", "\t\tif c.ResidenceDays != Never && c.ResidenceDays < n {", "\t\tif c.ResidenceDays != Never && c.ResidenceDays < 0 {", "a residence below N is refused (TR29)"),
    ("tiering/plan.go", "\t\tif u.PublishedAt.Add(grace).After(now) {", "\t\tif u.PublishedAt.After(now) {", "the release waits for the grace"),
    ("tiering/rows.go", "\t\tif v == nil {\n\t\t\tcontinue\n\t\t}\n\t\ttyp, ok := types[name]", "\t\tif v == nil {\n\t\t\tv = \"\"\n\t\t}\n\t\ttyp, ok := types[name]", "a null is not written"),
]
