# C6 P3 rerun: the three survivors of mutants.py after the tests and the code were tightened (a principal who edits
# every opportunity but does not assign; the won lock in one place; the older version checked before the newer one
# is sent again).
TITLE = "crm/opportunity 3.0.0: the three survivors again"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOFLAGS": "-mod=mod", "GOWORK": "off"}
MUTANTS = [
    ("internal/opportunities/commands.go", "	if owner != actor {", "	if false && owner != actor {",
     "OP01/OP04: another owner without the assign operation"),
    ("internal/opportunities/changes.go", "		if o.Stage == core.StageWon && locked {", "		if false && o.Stage == core.StageWon && locked {",
     "OP02: a won opportunity's amount changes"),
    ("internal/quotes/sales.go", "WHERE sales_link.version < EXCLUDED.version", "WHERE true", "OP08: an older version overwrites"),
]
