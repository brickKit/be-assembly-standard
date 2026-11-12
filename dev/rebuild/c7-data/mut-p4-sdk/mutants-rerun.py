TITLE = "be-sdk-go alpha.123 flow: the two survivors after the added cases"
BUILD = ["go", "vet", "-tags", "integration", "./flow/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./flow/"]
MUTANTS = [
    ("flow/decisions.go", "\t\t\t\tWHEN d.by_account = $3 THEN 1\n", "\t\t\t\tWHEN d.by_account = $3 THEN 9\n", "P17.14 a repeat replays the caller's decided task"),
    ("flow/decisions.go", "key = \"flow:\" + task + \":\" + string(c)", "key = \"flow:\" + task", "P17.14 the default key"),
]
