# C6 P3: crm/opportunity 3.0.0 (OP01-OP08, the funnel). Each mutant must turn the integration tests red.
TITLE = "crm/opportunity 3.0.0: OP01-OP08 and the funnel"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOFLAGS": "-mod=mod", "GOWORK": "off"}
C, M, Q, F = ("internal/opportunities/changes.go", "internal/opportunities/commands.go", "internal/quotes/sales.go",
              "internal/forecast/funnel.go")
MUTANTS = [
    (M, "	if owner != actor {", "	if false && owner != actor {", "OP01/OP04: another owner without the assign operation"),
    (C, "	if cur.Stage == core.StageWon && locked {", "	if false && cur.Stage == core.StageWon && locked {",
     "OP02: a won opportunity's amount changes"),
    (C, "cmd == CmdAdvance && to <= from", "cmd == CmdAdvance && to < from", "OP03: advance to the same stage"),
    (C, "		if cmd == CmdRevert {", "		if false && cmd == CmdRevert {", "OP03: a revert without a reason"),
    (C, "o.Stage, o.Probability = *o.StageBeforeClose, *o.probabilityBeforeClose",
     "o.Stage, o.Probability = *o.StageBeforeClose, defaultProbability(*o.StageBeforeClose)",
     "OP07: reopening forgets the probability"),
    (Q, "WHERE sales_link.version < EXCLUDED.version", "WHERE true", "OP08: an older version overwrites"),
    (Q, "			if d.Currency != o.Currency {", "			if false && d.Currency != o.Currency {",
     "OP08: another currency's total as the won amount"),
    (Q, "UPDATE quote_request SET state = 'rejected'", "UPDATE quote_request SET state = 'requested'",
     "OP08: a refusal not marked"),
    (F, "const value = `CASE WHEN o.stage = 'won' THEN o.won_amount ELSE o.amount END`", "const value = `o.amount`",
     "funnel: won counts the expected amount"),
    ("internal/core/rules.go", "		if v := c.Query(k); v != \"\" && !UUIDForm.MatchString(v) {",
     "		if v := c.Query(k); false && v != \"\" && !UUIDForm.MatchString(v) {", "funnel/list: a malformed filter fails the query"),
]
