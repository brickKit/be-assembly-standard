TITLE = "be-sdk-go alpha.124 flow: a step of a position or a person bound at the start"
BUILD = ["go", "vet", "-tags", "integration", "./flow/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./flow/"]
MUTANTS = [
    ("flow/kernel.go", "\tif b.PositionID != \"\" {\n\t\treturn Position\n\t}\n\treturn Person", "\treturn Position", "P17.3 a person binding resolves to the person"),
    ("flow/kernel.go", "\tif b.PositionID != \"\" {\n\t\treturn Position\n\t}\n\treturn Person", "\treturn Person", "P17.3 a position binding resolves to the holders"),
    ("flow/instance.go", "if pos == person || (st.Rule", "if (st.Rule", "P17.3 both or neither fails the start"),
    ("flow/decisions.go", "kind(d.Steps[i.Step-1], b) == Position && s.Task == Pending", "d.Steps[i.Step-1].Rule != Person && s.Task == Pending", "P17.10 the qualification by the bound kind"),
]
