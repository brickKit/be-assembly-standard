TITLE = "infra/notification 3.0.2: the consistency exam's fixes (C8 P6)"
BUILD = ["go", "vet", "-tags", "integration", "./itest/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off", "GOFLAGS": "-mod=mod"}
MUTANTS = [
    ("internal/intents/intents.go", "SenderIsSource: in.Sender == owner && e.Source == \"urn:be:\"+owner && e.Stream == sources.Stream(owner),", "SenderIsSource: in.Sender == strings.TrimPrefix(e.Source, \"urn:be:\"),", "M1 the sender is the stream's owner"),
    ("internal/delivery/delivery.go", "\t\tif had {\n\t\t\tcontinue\n\t\t}\n", "", "M3 a position is expanded once"),
    ("internal/intents/intents.go", "AND reason = $3)`, from, intentID, reason).Scan(&seen); err != nil || seen {", "AND reason = $3)`, from, intentID, reason).Scan(&seen); err != nil || false {", "S3 a redelivered refusal is recorded once"),
    ("internal/delivery/route.go", "\tcase c.Mandatory: // in-app is where a mandatory category falls back to: written even when expired (P18.6)\n\t\treturn core.Written\n\tcase expired:\n\t\treturn core.Expired", "\tcase expired:\n\t\treturn core.Expired\n\tcase c.Mandatory:\n\t\treturn core.Written", "S1 a mandatory category is written when expired"),
]
