TITLE = "be-sdk-go alpha.80 in progress (item 4 T7), round 2: round 1's mutant that did not build, rewritten (round 1's survivor was an equivalent mutant: the redundant mark is removed)"
BUILD = ["go", "vet", "-tags", "integration", "./events/", "./launcher/"]
TEST = ["go", "test", "-count=1", "-p", "1", "-tags", "integration", "-run",
        "TestResendFromTheAskedPosition|TestRedeliveryAfterTheConsumersDatabaseWentBack", "./events/", "./launcher/"]
MUTANTS = [
    ("events/resend.go", "\t\t\tbeyond = after == nil || after.Less(purged)", "\t\t\tbeyond = after == nil || purged.Less(Point{})", "a start before the purge is not beyond the retention"),
]
