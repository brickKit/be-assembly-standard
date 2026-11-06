TITLE = "be-ops alpha.11: freezing again from verifying or read-only (RC75); the double failures in step 9 (RC22)"
BUILD = ["go", "vet", "./internal/recovery/"]
TEST = ["go", "test", "-count=1", "./internal/recovery/"]
MUTANTS = [
    ("internal/recovery/state.go", "\t\tif st.State == Verifying || st.State == ReadOnly { // frozen again: steps 7 on are to be done again", "\t\tif false { // frozen again: steps 7 on are to be done again", "steps 7 on are done again"),
    ("internal/recovery/state.go", "\t\tif st.State == Running {\n\t\t\treturn fmt.Errorf(\"announce first", "\t\tif st.State != Frozen && st.State != Restoring {\n\t\t\treturn fmt.Errorf(\"announce first", "a freeze from verifying or read-only is allowed"),
    ("internal/recovery/state.go", "(approver == \"\" || reason == \"\")", "(approver == \"\")", "why is recorded too"),
    ("internal/recovery/verifyplan.go", "\t\tif err != nil || at.Before(t) {\n\t\t\tcontinue\n\t\t}\n\t\tout = append(out, EvidenceLoss{", "\t\tif err != nil {\n\t\t\tcontinue\n\t\t}\n\t\tout = append(out, EvidenceLoss{", "only after T"),
    ("internal/recovery/order.go", "\t\tcase any1(phases).Category == DoubleFailureCategory:", "\t\tcase any1(phases).Category == \"nothing\":", "a double failure is not replayed"),
    ("internal/recovery/verifycalls.go", "\tif rep.EvidenceLoss = DoubleFailures(stored, t); len(rep.EvidenceLoss) == 0 {", "\tif rep.EvidenceLoss = DoubleFailures(stored, t.Add(time.Hour)); len(rep.EvidenceLoss) == 0 {", "the loss lists them"),
]
