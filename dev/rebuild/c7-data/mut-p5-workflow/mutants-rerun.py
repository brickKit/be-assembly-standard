TITLE = "infra/workflow 3.0.0: the survivor after the added case"
BUILD = ["go", "vet", "-tags", "integration", "./itest/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
MUTANTS = [
    ("internal/worklist/worklist.go", "\twhere := append([]string{`t.state = 'pending'`, `EXISTS", "\twhere := append([]string{`t.state <> 'x'`, `EXISTS", "WF03 pending only"),
]
