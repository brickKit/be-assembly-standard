TITLE = "infra/workflow 3.0.0: the worklist (C7 P5)"
BUILD = ["go", "vet", "-tags", "integration", "./itest/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
MUTANTS = [
    ("internal/sources/sources.go", "\tcase known && slices.Contains(p.Previous, from):\n\t\treturn \"\"\n", "", "WF01 the previous publisher's own task"),
    ("internal/sources/sources.go", "\tcase known && slices.Contains(p.Previous, from):", "\tcase slices.Contains(p.Previous, from):", "WF01 a previous publisher's new task refused"),
    ("internal/sources/sources.go", "\tcase from == p.Current:\n\t\treturn \"\"\n", "\tcase true:\n\t\treturn \"\"\n", "WF01 only the chosen publisher"),
    ("internal/projections/projections.go", "json.Unmarshal(e.Data, &p) != nil || p.Component != from ||", "json.Unmarshal(e.Data, &p) != nil ||", "WF09 the projection's component is its sender"),
    ("internal/projections/projections.go", "\t\tWHERE task.version < excluded.version`", "\t\tWHERE task.version <= excluded.version + 1`", "WF02 an older version is dropped"),
    ("internal/projections/projections.go", "\t\tAND current AND NOT principal = ANY($3::text[])`", "\t\tAND current AND principal = ANY($3::text[]) AND false`", "WF02 the current candidates replaced"),
    ("internal/projections/projections.go", "\t_, err := m.RT.Audit.Write(ctx, tx, audit.Record{", "\t_, err := func(audit.Record) (string, error) { return \"\", nil }(audit.Record{", "WF01 each refusal's security record"),
    ("internal/projections/projections.go", "\t\treturn seen(ctx, tx, from, \"last_heartbeat\")", "\t\treturn nil", "WF06 the heartbeat"),
    ("internal/worklist/worklist.go", "coalesce(greatest(p.last_heartbeat, p.last_projection), '-infinity') < now() - $1::interval`", "false AND $1::interval IS NULL`", "WF06 stale"),
    ("internal/worklist/worklist.go", "x.principal = $2))`}, q.where...)", "x.principal = $2 AND x.current))`}, q.where...)", "WF04 the ever-candidates' done list"),
    ("internal/worklist/worklist.go", "\t\t\t\tAND x.principal = $4))`, m.StaleAfter.String(), component, id, me)", "\t\t\t\tAND x.principal = $4 AND x.current))`, m.StaleAfter.String(), component, id, me)", "WF05 an ever-candidate still reads it"),
    ("internal/worklist/worklist.go", "Path: \"/be/flow/tasks/\" + t.id + \"/decisions\"}\n\treturn t, err", "Path: \"/be/flow/tasks/\" + t.id}\n\treturn t, err", "WF05 the action entry"),
    ("internal/worklist/worklist.go", "\twhere := append([]string{`t.state = 'pending'`, `EXISTS", "\twhere := append([]string{`t.state <> 'x'`, `EXISTS", "WF03 pending only"),
]
