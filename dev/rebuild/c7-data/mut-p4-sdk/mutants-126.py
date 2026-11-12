TITLE = "be-sdk-go alpha.126 flow: the employee projection's change resolves again; no directory, not qualified"
BUILD = ["go", "vet", "-tags", "integration", "./flow/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./flow/"]
MUTANTS = [
    ("flow/routes.go", "\tif !due {\n\t\treturn nil\n\t}", "\tif due {\n\t\treturn nil\n\t}", "P17.8 queued only while tasks wait"),
    ("flow/routes.go", "\t\tAND NOT EXISTS (SELECT 1 FROM be_work_item WHERE job = $1 AND state = 'pending')`", "\t\tAND $1 <> ''`", "P17.8 not a second one while one waits"),
    ("flow/decisions.go", "\t\tif k.Directory == nil { // the deployment lost its employee directory: nothing proves the holder (P17.8)\n\t\t\ts.Qualification = NotQualified\n\t\t} else {", "\t\tif k.Directory == nil {\n\t\t} else {", "P17.10 no directory: not qualified"),
]
