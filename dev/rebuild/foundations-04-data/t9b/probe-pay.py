TITLE = "Go probe 3.2.41 in progress (item 4 T9b-3/4): the payment's adapter against the fake external system"
BUILD = ["bash", "-c", "cd probes/go && go vet ./..."]
TEST = ["uv", "run", "--frozen", "--project", "conformance", "pytest", "-q", "-x", "conformance/tests/test_external_profile.py"]
P = "probes/go/probe/payments.go"
MUTANTS = [
    (P, "\tcase errors.As(err, &st) && (st.Status == 400 || st.Status == 422):\n\t\treturn extcmd.Rejected", "\tcase errors.As(err, &st) && (st.Status == 400 || st.Status == 422):\n\t\treturn extcmd.MaybeReached", "a refusal taken as maybe reached"),
    (P, "\tcase errors.As(err, &st) && st.Status == 429:\n\t\treturn extcmd.NotReached", "\tcase errors.As(err, &st) && st.Status == 429:\n\t\treturn extcmd.MaybeReached", "a rate limit taken as maybe reached"),
    (P, "\tif errors.As(err, &st) && st.Status == 404 {\n\t\treturn extcmd.Answer{Found: false}, nil\n\t}", "", "not found taken as the query down"),
]
