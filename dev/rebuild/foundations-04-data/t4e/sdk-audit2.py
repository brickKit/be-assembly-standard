TITLE = "(the one that did not build, rewritten) be-sdk-go alpha.88 in progress (item 4 T4e): the audit gaps (AU07, AU08, AU10, AU15, AU22, AU23)"
BUILD = ["go", "vet", "-tags", "integration", "./audit/", "./authz/", "./internal/host/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./audit/", "./authz/", "./internal/host/"]
A, T, D, H = "audit/audit.go", "audit/transfer.go", "authz/defs.go", "internal/host/build.go"
MUTANTS = [
    (H, "\t\t\tif f.Class == authz.Restricted {", "\t\t\tif f.Class == authz.Restricted && false {", "the restricted fields not taken from the definitions"),
]
