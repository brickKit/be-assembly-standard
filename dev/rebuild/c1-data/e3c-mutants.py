TITLE = "mdm/employee E3c: the employee's lifecycle"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
MUTANTS = [
    ("internal/employees/employees.go", "shaped := sdkauthz.Mask(core.ResourceOf(core.Employees), e, d.Fields)",
     "shaped := sdkauthz.Mask(core.ResourceOf(core.Employees), e, append(d.Fields, \"personal\"))", "the personal data is masked for a grant that does not read it"),
    ("internal/employees/employees.go", "\tif in.HireDate > today {", "\tif in.HireDate > today && false {",
     "a hire after today is pre_hire"),
    ("internal/employees/employees.go", "\t\tif d <= today {", "\t\tif d <= today || true {", "a termination on a later date waits for it"),
    ("internal/employees/employees.go", "\t\t\treturn core.ErrNumber.New(\"employee number \" + in.EmployeeNo + \" belongs to another employee\")",
     "\t\t\tout = cur\n\t\t\treturn nil", "the number is the legal entity's once"),
]
