TITLE = "infra/audit 3.0.15 in progress (item 4 T4d): the evidence store (P12.9-P12.13), go test -tags integration ./audit/"
BUILD = ["go", "vet", "-tags", "integration", "./audit"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./audit/"]
F = "audit/evidence.go"
MUTANTS = [
    (F, "\tcase err == nil && digest == r.GetDigest():", "\tcase err == nil:", "another digest under the same (id, phase) is a duplicate"),
    (F, "\t\t\tif json.Unmarshal(raw, &intent) != nil || !sameSubject(intent, e) {", "\t\t\tif json.Unmarshal(raw, &intent) != nil {", "a conclusion need not match its intent"),
    (F, "\t\tif bad[i] == nil && parsed[i].Recorder.Component != caller {", "\t\tif bad[i] == nil && parsed[i].Recorder.Component != caller && false {", "a component appends another's evidence"),
    (F, "\tif canon.DigestBytes(EvidenceRecordType, 1, raw) != digest {", "\tif false {", "a wrong digest is kept"),
    (F, "\t\t\tWHERE seq > $1 AND ($2 = '' OR recorder = $2) AND ($3 = '' OR category = $3) ORDER BY seq LIMIT $4`,", "\t\t\tWHERE seq > $1 AND ($3 = '' OR category = $3) AND $2 = $2 ORDER BY seq LIMIT $4`,", "the recorder filter is ignored"),
    (F, "\t\tout.Records, out.More = out.Records[:limit], true", "\t\tout.Records = out.Records[:limit]", "more is never set"),
    (F, "\tm.rt.Logger.Error(\"an evidence record conflicts with what the store keeps: an integrity event\", \"event\",", "\tm.rt.Logger.Info(\"an evidence record conflicts with what the store keeps: an integrity event\", \"event-\",", "a conflict raises no integrity event"),
    ("audit/audit.go", '\t\t"List":   {Operation: OpList, Callers: readers}})', '\t\t"List":   {Operation: OpList, Callers: append(readers, grpcx.AnyComponent)}})', "anyone lists the evidence"),
]
