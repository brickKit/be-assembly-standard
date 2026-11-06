TITLE = "infra/audit 3.0.28: the categories are the protocol's (trust_material removed, A148)"
BUILD = ["go", "vet", "./audit/"]
TEST = ["go", "test", "-count=1", "./audit/"]
MUTANTS = [
    ("audit/evidence.go", "\"external_command_outcome\",", "\"external_command_outcome\", \"trust_material\",", "the category is gone"),
]
