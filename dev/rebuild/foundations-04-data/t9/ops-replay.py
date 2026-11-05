TITLE = "be-ops in progress (item 4 T9d): step 6 (replay: order, calls, alerts, addresses) and 6.8 (keys)"
BUILD = ["go", "vet", "./internal/recovery/"]
TEST = ["go", "test", "-count=1", "./internal/recovery/"]
O, R, S, K, T = "internal/recovery/order.go", "internal/recovery/replay.go", "internal/recovery/replaystep.go", "internal/recovery/keys.go", "internal/recovery/state.go"
MUTANTS = [
    (O, "\tcase a.Generation != b.Generation:\n\t\treturn a.Generation < b.Generation\n", "", "the epoch's generation is not compared"),
    (O, "\t\tcase has(phases, \"cancelled\"):", "\t\tcase false:", "a cancelled record is replayed"),
    (O, "\t\t\tif r.IntentOnly && r.Category == \"security_tightening\" {", "\t\t\tif false {", "the authorization member's intent-only tightenings are not deferred"),
    (O, "\t\treturn !a.IntentOnly\n", "\t\treturn a.IntentOnly\n", "intent-only records go first"),
    (R, "\t\t\t\tsubjects[r.Subject] = true // a re-execution that failed: its subject closed (protocol 15)", "\t\t\t\t_ = r.Subject", "a failed re-execution's subject is not closed"),
    (R, "\t\t\tif r.IntentOnly {\n\t\t\t\trep.Review = append(rep.Review, r.ID)\n\t\t\t}", "\t\t\t_ = r.IntentOnly", "an applied intent-only record is not listed for review"),
    (R, "\tfor deadline := time.Now().Add(wait); !applied; {", "\tfor deadline := time.Now().Add(wait); false; {", "6.4 is not waited for"),
    (R, "\tif len(rep.Check.Unprovable) > 0 {", "\tif false {", "an unprovable check passes"),
    (S, "\t\tcase l.Err == nil && rec.Recorder.Component == l.Record.Writer.Component:", "\t\tcase l.Err == nil:", "an intent signed by another than its recorder is trusted"),
    (S, "\t\tif read && rec.Subject != \"\" {\n\t\t\treview = append(review, rec.Subject)", "\t\tif false {\n\t\t\treview = append(review, rec.Subject)", "an untrusted intent's subject is not closed"),
    (S, "\t\t\t\tout[c.ID] = fmt.Sprintf(\"%s:%d\", alias.Replace(c.ID+\"-\"+c.Version), port.Port)", "\t\t\t\tout[c.ID] = fmt.Sprintf(\"%s:%d\", alias.Replace(c.ID), port.Port)", "the address lacks the version"),
    (K, "\t\tif err := os.Rename(path, path+suffix); err != nil {", "\t\tif err := os.Remove(path); err != nil {", "the old key file is not kept"),
    (K, "pem.EncodeToMemory(&pem.Block{Type: \"PRIVATE KEY\", Bytes: der}), 0o600)", "pem.EncodeToMemory(&pem.Block{Type: \"PRIVATE KEY\", Bytes: der}), 0o644)", "a key file readable by others"),
    (T, "\t\tif st.State != Restoring || !done(StepReplay) {", "\t\tif st.State != Restoring {", "keys before the replay"),
]
