TITLE = "(the one that did not build, rewritten) Go probe 3.2.41 in progress (item 4 T9b-3/4): the payment's adapter against the fake external system"
BUILD = ["bash", "-c", "cd probes/go && go vet ./..."]
TEST = ["uv", "run", "--frozen", "--project", "conformance", "pytest", "-q", "-x", "conformance/tests/test_external_profile.py"]
P = "probes/go/probe/payments.go"
MUTANTS = [
    (P, "\tif errors.As(err, &st) && st.Status == 404 {", "\tif errors.As(err, &st) && st.Status == 404 && false {", "not found taken as the query down"),
]
