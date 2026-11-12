TITLE = "be-sdk-go alpha.125 flow: a decided task is published after its instance changed"
BUILD = ["go", "vet", "-tags", "integration", "./flow/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./flow/"]
MUTANTS = [
    ("flow/decisions.go", "\tfor _, id := range append([]string{t.ID}, others...) {", "\tfor _, id := range others {", "P17.15 the decided task is published"),
    ("flow/decisions.go", "\tfor _, id := range append([]string{t.ID}, others...) {", "\tfor _, id := range []string{t.ID} {", "P17.15 the superseded others are published"),
]
