TITLE = "mdm/org 3.0.18 in progress (item 4 T9c), round 2: the mutant that did not build, rewritten"
BUILD = ["go", "vet", "-tags", "integration", "./org/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./org/"]
MUTANTS = [("org/replay.go", "\t\tif strings.HasPrefix(p.Path+\"/\", u.Path+\"/\") {", "\t\tif strings.HasPrefix(p.Path+\"/\", u.Path+\"/\") && false {", "a move under its own subtree is applied")]
