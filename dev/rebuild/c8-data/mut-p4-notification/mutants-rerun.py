TITLE = "infra/notification 3.0.0: intents, delivery, inbox, preferences (C8 P4), the rerun"
BUILD = ["go", "vet", "-tags", "integration", "./itest/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad/c8work/go.work"}
MUTANTS = [
    ('internal/intents/intents.go', '\tcase Duplicate:\n\t\treturn nil\n', '\tcase Duplicate:\n\t\treturn insert(ctx, tx, in, "pending")\n', 'P18.9 a duplicate is not delivered again'),
    ('internal/delivery/route.go', '\tcase c.Mandatory:\n\t\treturn core.Written\n', '', 'NT07 a mandatory category ignores the preference'),
    ('internal/delivery/delivery.go', '\t\t\tif !seen[h] {\n\t\t\t\tseen[h] = true\n\t\t\t\tprincipals = append(principals, h)\n\t\t\t}', '\t\t\tprincipals = append(principals, h)', 'NT05 one delivery per principal'),
    ('internal/delivery/delivery.go', '\tcase !complete:\n', '\tcase false && !complete:\n', 'NT06 an incomplete projection is not used'),
    ('internal/delivery/delivery.go', '\tif waiting {\n', '\tif false && waiting {\n', 'NT05 a waiting position keeps the intent pending'),
]
