TITLE = "be-sdk-go alpha.77 in progress (item 4 T3): s3sig.Request against the AWS signer"
BUILD = ["go", "vet", "./internal/s3sig"]
TEST = ["go", "test", "-count=1", "./internal/s3sig"]
MUTANTS = [
    ("internal/s3sig/sigv4.go", "	for n, v := range extra {\n		h[n] = v\n	}", "	_ = extra", "the extra headers are not signed"),
    ("internal/s3sig/sigv4.go", "	if query != \"\" {\n		u += \"?\" + query\n	}", "", "the query is left off the URL"),
]
