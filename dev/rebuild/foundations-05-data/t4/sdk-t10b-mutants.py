TITLE = "be-sdk-go tiering (T10b): the route chosen at deployment"
BUILD = ["go", "vet", "./tiering/"]
TEST = ["bash", "-c", "go test -count=1 -run 'TestARouteChosenAtDeployment|Vectors|TestATextArrayIsNFC' ./tiering/"]
MUTANTS = [
    ("tiering/member.go", "\t\t\tif !slices.Contains(cl.Routes, raw) {", "\t\t\tif !slices.Contains(cl.Routes, raw) && false {", "a route the class does not allow refuses the start"),
    ("tiering/member.go", "\t\t\tcl.Routes = append([]string{raw}, slices.DeleteFunc(slices.Clone(cl.Routes), func(r string) bool { return r == raw })...)", "\t\t\t_ = raw", "the chosen route is the target"),
    ("tiering/rows.go", "\t\tout[i] = canon.Text(s)", "\t\tout[i] = s", "each element is NFC (now by the vector too)"),
]
