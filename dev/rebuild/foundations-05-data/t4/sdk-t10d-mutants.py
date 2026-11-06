TITLE = "be-sdk-go tiering (T10d): a leaf's composite key, the columns check, text arrays"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -run 'TestAClassDeclaration|Vectors|RoundTrip|WrittenAgain' ./tiering/ && go test -count=1 -tags integration -run 'TestAClassMustDeclareItsTables|TestAnAggregateOfThreeLevels' ./tiering/"]
MUTANTS = [
    ("tiering/rows.go", "\t\ts, ok := e.(string)\n\t\tif !ok {\n\t\t\treturn nil, refused(TypeTextArray, v)\n\t\t}\n\t\tout[i] = canon.Text(s)", "\t\ts, _ := e.(string)\n\t\tout[i] = canon.Text(s)", "an array with a null element is refused"),
    ("tiering/rows.go", "\t\tout[i] = canon.Text(s)", "\t\tout[i] = s", "each element is NFC"),
    ("tiering/class.go", "\t\tif parent, ok := c.parent(ch); ok && parent.PK == \"\" {", "\t\tif parent, ok := c.parent(ch); ok && parent.PK == \"-\" {", "a parent keeps a single-column key"),
    ("tiering/class.go", "\t\tif (t.PK == \"\") == (len(t.Key) == 0) {", "\t\tif t.PK == \"\" && len(t.Key) == 0 {", "a table has one kind of key"),
    ("tiering/member.go", "\t\t\t\tcase !ok:\n", "\t\t\t\tcase !ok && false:\n", "an undeclared column refuses the start"),
    ("tiering/member.go", "\t\t\t\tcase !slices.Contains(sqlTypes[declared], typ):", "\t\t\t\tcase false && !slices.Contains(sqlTypes[declared], typ):", "a column of another type refuses the start"),
    ("tiering/member.go", "\t\t\t\tif _, ok := have[name]; !ok {", "\t\t\t\tif _, ok := have[name]; !ok && false {", "a declared column the table lacks refuses the start"),
    ("tiering/reads.go", "\t\t\tif ch.PK != \"\" { // a possible parent", "\t\t\tif ch.PK != \"\" && false { // a possible parent", "a read maps a parent's rows to their roots"),
    ("tiering/parquet.go", "\tcase TypeTextArray:\n\t\treturn textArray(string(v.ByteArray()))", "\tcase TypeTextArray:\n\t\treturn string(v.ByteArray()), nil", "an object's text array is read back as one"),
]
