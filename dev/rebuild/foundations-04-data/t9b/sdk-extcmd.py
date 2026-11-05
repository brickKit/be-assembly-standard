TITLE = "be-sdk-go alpha.89 in progress (item 4 T9b-2): the external commands (chapter 13)"
BUILD = ["go", "vet", "-tags", "integration", "./extcmd/", "./internal/host/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./extcmd/"]
S, C = "extcmd/state.go", "extcmd/commands.go"
MUTANTS = [
    (S, "\t\tif past {\n\t\t\treturn Unknown, \"claimed past the resend deadline\"\n\t\t}", "", "claimed past the deadline"),
    (S, "\t\tcase MaybeReached:\n\t\t\treturn Unknown, \"may have been processed: query first\"", "\t\tcase MaybeReached:\n\t\t\treturn RetryWait, \"may have been processed: query first\"", "a maybe-reached send retried without a query"),
    (S, "\treturn false, \"the earlier request may still land\"", "\treturn true, \"the earlier request may still land\"", "not found resent anyway"),
    (S, "\tm := max(c.DedupeWindow/10, MinMargin)", "\tm := c.DedupeWindow/10", "no minimum margin"),
    (S, "\tif terminal(s) {\n\t\treturn s, \"a terminal state absorbs every later result\"\n\t}", "", "a terminal state moved"),
    (C, "\tif stored != digest || op != operation {", "\tif op != operation {", "a reused reference with other parameters"),
    (C, "\t\t\tif c.QueryOnly { // P13.10: they stay where they are", "\t\t\tif false { // P13.10: they stay where they are", "query-only sends"),
    (C, "\t\tcase Sending: // due while sending: its claimant is gone (P13.5)\n\t\t\tnext, why := Step(r.Facts, Event{Kind: LeaseLost}, r.caps, r.now)", "\t\tcase Sending: // due while sending: its claimant is gone (P13.5)\n\t\t\tnext, why := Step(r.Facts, Event{Kind: Claim}, r.caps, r.now)", "a takeover sends again"),
    (C, "\tif r.caps.Irrevocable && !c.issued(ctx, r) {", "\tif false && !c.issued(ctx, r) {", "an irrevocable command sent without its issue record"),
    (C, "\treturn p.Intent == \"store\" || p.Intent == \"alert\"", "\treturn true", "a lost issue record taken as written"),
    (C, "\t\tr.ResendDeadline = Deadline(r.Facts, r.caps)", "\t\tr.ResendDeadline = nil", "the deadline not written"),
    (C, "\tcase RetryWait:\n\t\treturn r.now.Add(backoff(attempts))", "\tcase RetryWait:\n\t\treturn r.now", "no backoff"),
]
