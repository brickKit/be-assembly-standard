TITLE = "be-sdk-go tiering (T10a): nested children, the retention at deployment, the standard routes"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/", "./launcher/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -run 'TestAClassDeclaration|TestARetentionGivenAtDeployment' ./tiering/ && go test -count=1 -tags integration -run 'TestAnAggregateOfThreeLevels' ./tiering/ && go test -count=1 -tags integration -run 'TestAComponentWithClassesServes' ./launcher/"]
MUTANTS = [
    ("tiering/class.go", "\t\tif _, ok := c.parent(ch); !ok {", "\t\tif _, ok := c.parent(ch); !ok && false {", "a child's parent must exist"),
    ("tiering/class.go", "\t\t} else if c.depth(ch) < 0 {", "\t\t} else if c.depth(ch) < -1 {", "children may not go round in a cycle"),
    ("tiering/class.go", "\treturn fmt.Sprintf(\"(SELECT %s FROM %s %s WHERE %s.%s = %s.%s)\", c.rootExpr(parent, p), ident(parent.Name), p, p,\n\t\tident(parent.PK), alias, ident(ch.FK))", "\t_, _ = parent, p\n\treturn alias + \".\" + ident(ch.FK) + \"::text\"", "a grandchild's root is found up the chain"),
    ("tiering/barrier.go", "\t\t\tif parent, ok := c.child(ch.Parent); ok {", "\t\t\tif parent, ok := c.child(ch.Parent); ok && false {", "the barrier finds a grandchild's root"),
    ("tiering/class.go", "\t\t\treturn c.depth(out[i]) > c.depth(out[j])", "\t\t\treturn c.depth(out[i]) < c.depth(out[j])", "deletes go deepest first"),
    ("tiering/reads.go", "\t\t\tif parent, ok := cl.child(ch.Parent); ok {\n\t\t\t\tif k, ok = rootOf[parent.Name][k]; !ok {", "\t\t\tif parent, ok := cl.child(ch.Parent); ok && false {\n\t\t\t\tif k, ok = rootOf[parent.Name][k]; !ok {", "a read puts a grandchild under its root"),
    ("tiering/transfer.go", "\t\t\tif err != nil || !keys[parent.Name][fmt.Sprint(v)] {", "\t\t\tif err != nil || !keys[cl.Root.Name][fmt.Sprint(v)] && parent.Name != \"\" {", "the integrity check goes level by level"),
    ("tiering/member.go", "\t\t\tcl.Retention = r", "\t\t\t_ = r", "the deployment's retention replaces the declared one"),
    ("tiering/member.go", "\tif err1 != nil || err2 != nil || lo <= 0 || hi < lo || basis == \"\" {", "\tif err1 != nil || err2 != nil || lo <= 0 || basis == \"\" {", "the longest not below the shortest"),
    ("tiering/routes.go", "\t\tif cl.HoldOperation != \"\" {\n\t\t\tr.POST(base+\"/holds\"", "\t\tif cl.HoldOperation == \"-\" {\n\t\t\tr.POST(base+\"/holds\"", "the hold routes are there"),
    ("internal/host/build.go", "\tif rt.Tiering != nil { // holds, approvals and export status", "\tif rt.Tiering != nil && false { // holds, approvals and export status", "the host registers the routes"),
]
