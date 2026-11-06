TITLE = "be-sdk-go tiering (T10a, the three again): nested children, the retention at deployment, the standard routes"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/", "./launcher/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -run 'TestAClassDeclaration|TestARetentionGivenAtDeployment' ./tiering/ && go test -count=1 -tags integration -run 'TestAnAggregateOfThreeLevels' ./tiering/ && go test -count=1 -tags integration -run 'TestAComponentWithClassesServes' ./launcher/"]
MUTANTS = [
    ("tiering/class.go", "\t\tif _, ok := c.parent(ch); !ok {", "\t\tif _, ok := c.parent(ch); !ok && false {", "a child's parent must exist"),
    ("tiering/class.go", "\treturn fmt.Sprintf(\"(SELECT %s FROM %s %s WHERE %s.%s = %s.%s)\", c.rootExpr(parent, p), ident(parent.Name), p, p,\n\t\tident(parent.PK), alias, ident(ch.FK))", "\t_, _ = parent, p\n\treturn alias + \".\" + ident(ch.FK) + \"::text\"", "a grandchild's root is found up the chain"),
    ("tiering/transfer.go", "\t\t\tif err != nil || !keys[parent.Name][fmt.Sprint(v)] {", "\t\t\tif err != nil || !keys[cl.Root.Name][fmt.Sprint(v)] && parent.Name != \"\" {", "the integrity check goes level by level"),
]
