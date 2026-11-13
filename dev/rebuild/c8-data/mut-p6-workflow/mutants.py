TITLE = "infra/workflow 3.0.7: the publisher is the stream's owner (C8 P6)"
BUILD = ["go", "vet", "-tags", "integration", "./itest/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off", "GOFLAGS": "-mod=mod"}
MUTANTS = [
    ("internal/projections/projections.go", "\tfrom := owner\n\tif strings.HasSuffix", "\tfrom := strings.TrimPrefix(e.Source, \"urn:be:\")\n\tif strings.HasSuffix", "WF01 the publisher is the stream's owner"),
    ("internal/projections/projections.go", "\t\te.Source != \"urn:be:\"+owner || !uuidForm", "\t\t!uuidForm", "WF01 the envelope's source names the owner"),
]
