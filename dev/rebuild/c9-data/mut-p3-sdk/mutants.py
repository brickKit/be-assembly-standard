TITLE = "be-sdk-go alpha.130: the storage port and the attachment categories (C9 P3)"
BUILD = ["go", "vet", "-tags", "integration", "./storage/", "./authz/", "./httpx/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./storage/", "./authz/", "./httpx/"]
ENV = {"GOWORK": "/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad/c9work/go.work", "GOFLAGS": ""}
MUTANTS = [
    ("storage/storage.go", "\t\textra[\"if-none-match\"] = \"*\"\n\t}\n\tresp, err := s.do(ctx, http.MethodPut, full, \"\", extra, bytes.NewReader(data), size)", "\t}\n\tresp, err := s.do(ctx, http.MethodPut, full, \"\", extra, bytes.NewReader(data), size)", "P19.3 put only when absent"),
    ("storage/storage.go", "\t\t\"if-none-match\": \"*\", \"x-amz-metadata-directive\": \"REPLACE\", \"content-type\": \"application/octet-stream\"}", "\t\t\"x-amz-metadata-directive\": \"REPLACE\", \"content-type\": \"application/octet-stream\"}", "P19.4 copy only when absent"),
    ("storage/storage.go", "\t\t\"if-none-match\": \"*\", \"x-amz-metadata-directive\": \"REPLACE\", \"content-type\": \"application/octet-stream\"}", "\t\t\"if-none-match\": \"*\"}", "P19.4 the destination's metadata rewritten"),
    ("storage/storage.go", "map[string]string{\"content-length\": strconv.FormatInt(size, 10), \"content-type\": contentType}, nil), nil", "map[string]string{\"content-type\": contentType}, nil), nil", "P19.6 the length signed"),
    ("storage/storage.go", "\t\tquery[\"response-content-disposition\"] = mime.FormatMediaType(\"attachment\", map[string]string{\"filename\": filename})\n\t\tquery[\"response-content-type\"] = \"application/octet-stream\"", "\t\tquery[\"response-content-disposition\"] = mime.FormatMediaType(\"attachment\", map[string]string{\"filename\": filename})", "P19.7 a saved file is a plain stream of bytes"),
    ("storage/storage.go", "\tcase code == http.StatusForbidden || code == http.StatusUnauthorized:\n\t\tcls = ErrDenied", "\tcase false:\n\t\tcls = ErrDenied", "P19.9 a refused credential is denied"),
    ("storage/storage.go", "\treturn s.public.Presign(s.secret(), http.MethodPut,", "\treturn s.signer.Presign(s.secret(), http.MethodPut,", "P19.6 the browsers' address"),
    ("authz/defs.go", "\t\t\tcase r.Fields[c.Field].Class == \"\":", "\t\t\tcase false:", "09a a category's field is the resource's"),
    ("httpx/context.go", "\th.Set(\"X-Content-Type-Options\", \"nosniff\")\n", "", "P12 a download is never sniffed"),
]
