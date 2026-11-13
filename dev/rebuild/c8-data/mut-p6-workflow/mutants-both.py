TITLE = "infra/workflow 3.0.7: both guards of the publisher removed (C8 P6)"
BUILD = ["go", "vet", "-tags", "integration", "./itest/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off", "GOFLAGS": "-mod=mod"}
MUTANTS = [
    ("internal/projections/projections.go", "\tfrom := owner\n\tif strings.HasSuffix(e.Type, core.TaskHeartbeatSuffix) {\n\t\tif e.Source != \"urn:be:\"+owner {\n\t\t\treturn nil // a heartbeat that names another component says nothing about this stream's owner\n\t\t}\n\t\treturn seen(ctx, tx, from, \"last_heartbeat\")\n\t}\n\tvar p projected\n\tdoc, err := jsonschema.UnmarshalJSON(bytes.NewReader(e.Data))\n\tif err != nil || contract.Validate(doc) != nil || json.Unmarshal(e.Data, &p) != nil || p.Component != from ||\n\t\te.Source != \"urn:be:\"+owner || !uuidForm", "\tfrom := strings.TrimPrefix(e.Source, \"urn:be:\")\n\tif strings.HasSuffix(e.Type, core.TaskHeartbeatSuffix) {\n\t\treturn seen(ctx, tx, from, \"last_heartbeat\")\n\t}\n\tvar p projected\n\tdoc, err := jsonschema.UnmarshalJSON(bytes.NewReader(e.Data))\n\tif err != nil || contract.Validate(doc) != nil || json.Unmarshal(e.Data, &p) != nil || p.Component != from ||\n\t\t!uuidForm", "WF01 back to the self-declared source (3.0.6)"),
]
