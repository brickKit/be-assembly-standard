TITLE = "be-sdk-go alpha.77 in progress (item 4 T3, second round: the conditional create tested through Append; the log mutant rewritten): runprofile (P12.1-P12.8), unit and integration tests against RustFS"
BUILD = ["go", "vet", "-tags", "integration", "./runprofile"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./runprofile/"]
F = "runprofile/runprofile.go"
MUTANTS = [
    (F, '\t\t"if-none-match": "*", "x-amz-object-lock-mode"', '\t\t"x-amz-object-lock-mode"', "a key may be written twice (no conditional create)"),
    (F, '"if-none-match": "*", "x-amz-object-lock-mode": "COMPLIANCE", "x-amz-object-lock-retain-until-date": until}', '"if-none-match": "*"}; _ = until', "no object lock on the record"),
    (F, '\tif _, err := s.o.Identity.VerifySigner(chain); err != nil {', '\tif _, err := s.o.Identity.VerifySigner(chain); err != nil && false {', "a signer under another trust root is accepted"),
    (F, '\t\tif r.Signature.Alg == "ES256" && ecdsa.VerifyASN1(pub, d[:], sig) {', '\t\tif r.Signature.Alg == "ES256" || ecdsa.VerifyASN1(pub, d[:], sig) {', "a changed body is accepted"),
    (F, '\tr.Signature = nil\n\traw, err := json.Marshal(r)', '\traw, err := json.Marshal(r)', "the signature is part of the signed bytes"),
    (F, '\t\tif json.Unmarshal(r.Body, &b) == nil && b.Value > max {', '\t\tif json.Unmarshal(r.Body, &b) == nil {', "the generation is the last record, not the largest"),
    (F, '\tif _, err := s.Append(ctx, kind, map[string]int64{"value": next}); err != nil {\n\t\treturn 0, err\n\t}\n\treturn next, nil', '\treturn next, nil', "an advance is used without being written to the run profile"),
    (F, '\t\tm = max(m, v)', '\t\t_ = v', "an advance ignores the values seen elsewhere"),
    (F, '\tif s.o.Webhook != "" {', '\tif s.o.Webhook == "never" {', "the webhook is not notified"),
    (F, '\t\ts.o.Log("the alert channel could not be written either", "event", "evidence_double_failure", "error", err.Error())', '\t\t_ = err', "the double failure is not logged"),
]
