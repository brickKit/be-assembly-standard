TITLE = "mdm/org 3.0.18 in progress (item 4 T9c): the replay of org_tightening"
BUILD = ["go", "vet", "-tags", "integration", "./org/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./org/"]
R = "org/replay.go"
MUTANTS = [
    (R, "\t\t\tu.State = \"retired\"\n\t\t\treturn nil", "\t\t\treturn nil", "a retirement is not re-applied"),
    (R, "\t\tif strings.HasPrefix(p.Path+\"/\", u.Path+\"/\") {", "\t\tif false {", "a move under its own subtree is applied"),
    (R, "\tif cur.State == state || cur.State == \"retired\" {\n\t\treturn nil\n\t}", "\tif true {\n\t\treturn nil\n\t}", "a legal entity's status is not re-applied"),
]
