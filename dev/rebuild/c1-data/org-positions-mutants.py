TITLE = "mdm/org 3.0.34 (C1 E0b): the positions' rules"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
MUTANTS = [
    ("internal/units/units.go", 'return core.ErrState.New("positions in it are still active: retire them first")',
     "_ = active", "a unit with an active position does not retire"),
    ("internal/positions/positions.go", "return change(m, c, in.Version, tightening.PositionRetirement,",
     "return change(m, c, in.Version, nil,", "retiring a position writes its intent and conclusion"),
    ("internal/positions/positions.go", 'return core.ErrState.New("the unit is retired: no new positions")',
     "_ = u", "no position in a retired unit"),
    ("internal/positions/positions.go", "if cur.Name == *in.Name && cur.UnitID == in.UnitID {",
     "if cur.Name == *in.Name {", "the same creation again is the same name in the same unit"),
    ("internal/replay/replay.go", "\t\treturn replayPosition(m, ctx, tx, rec.Object.ID)\n",
     "\t\treturn nil\n", "the replay retires the position again"),
    ("internal/positions/positions.go", "if version != nil && *version != cur.Version {",
     "if false && version != nil && *version != cur.Version {", "a stale version is refused"),
]
