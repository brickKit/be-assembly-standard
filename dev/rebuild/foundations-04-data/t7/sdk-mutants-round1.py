TITLE = "be-sdk-go alpha.80 in progress (item 4 T7): progress and redelivery (P6.36-P6.40), the events and launcher tests that cover them"
BUILD = ["go", "vet", "-tags", "integration", "./events/", "./launcher/", "./internal/host/"]
TEST = ["go", "test", "-count=1", "-p", "1", "-tags", "integration", "-run",
        "TestProgressVectors|TestResendFromTheAskedPosition|TestTheRedeliveryStartsAtTheSmallestProgress|TestPurgeKeepsUnpublishedAndRecentRows|TestRedeliveryAfterTheConsumersDatabaseWentBack",
        "./events/", "./launcher/"]
P, R, D, C, F, H = "events/progress.go", "events/resend.go", "events/redelivery.go", "events/consumer.go", "events/forwarder.go", "internal/host/member.go"
MUTANTS = [
    (P, "\t\tif ok && !starts[k].After(last.Add(-lifetime)) {", "\t\tif ok {", "a run shorter than L counts"),
    (P, "\t\t\treturn last.Add(-lifetime), true", "\t\t\treturn last, true", "the cut is the last handling, not L before it"),
    (P, "seq IS NOT NULL AND processed_at <= $2", "seq IS NOT NULL AND $2::timestamptz IS NOT NULL", "the progress is the largest position handled"),
    (C, "\t\t\tgen, tl, seq = e.Generation, e.Timeline, r.Seq", "\t\t\t_ = e", "the inbox keeps no source position"),
    (R, "\t\t\tm.MsgID = row.EventID + \"/resend/\" + request", "\t\t\tm.MsgID = \"\"", "a redelivery reuses the event's message identity"),
    (R, "\t\t\tbeyond = after == nil || after.Less(purged)", "\t\t\tbeyond = after == nil", "a start before the purge is not beyond the retention"),
    (R, "\t\t\tahead = after.Seq > last", "\t\t\tahead = false", "a start past the counter is not ahead"),
    (R, "\t\tahead = after.Seq > fork", "\t\tahead = false", "a start past the fork point is not ahead"),
    (R, "\t\t\tahead = true // an epoch this partition never had", "\t\t\tahead = false", "an unknown epoch is not ahead"),
    (D, "\t\tback = last != cur", "\t\tback = false", "a database that went back is not noticed"),
    (D, "\tif err := r.Settle(ctx, cur); err != nil {", "\tif err := error(nil); err != nil {", "the epoch is never recorded after the redelivery"),
    (D, "\t\t\tif sub := byName[s]; kind == \"beyond_retention\" && sub.Repair != nil {", "\t\t\tif sub := byName[s]; kind == \"beyond_retention\" && sub.Repair != nil && false {", "a read model is not repaired"),
    (D, "\t\t\tcase p.Less(cur.point):", "\t\t\tcase cur.point.Less(p):", "the start is the largest progress of the subscriptions"),
    (D, "\t\t\t\topen[k.Partition] = true // an earlier subscription has none here", "\t\t\t\t_ = open", "a partition an earlier subscription lacks still gets a start"),
    (H, "\t\tif err := events.StartRun(bg, c.DB, c.Sub.Name); err != nil { // a run of this subscription (P6.36)", "\t\tif err := error(nil); err != nil {", "a subscription's start is not recorded"),
    (F, "\t\t\tfor sp, p := range top {", "\t\t\tfor sp, p := range map[streamPart]Point{} {", "the purge notes no position"),
]
