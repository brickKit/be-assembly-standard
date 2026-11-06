TITLE = "be-sdk-go alpha.98: every SDK job says how it behaves in a recovery (retro R1)"
BUILD = ["go", "vet", "./internal/host/"]
TEST = ["go", "test", "-count=1", "-run", "EverySDKJob", "./internal/host/"]
F = "internal/host/recoveryjobs.go"
MUTANTS = [
    (F, "\tif _, ok := inRecovery[j.Name]; !ok {", "\tif _, ok := inRecovery[j.Name]; !ok && false {", "a job outside the table is refused"),
    (F, "\t\"be.work.cleanup\":        {why: \"not run: housekeeping of the member's own database, which goes back; once open\"},\n", "", "the table names every SDK job"),
    (F, "\t\"be.partitions.maintain\": {why: \"not run: the partitions ahead were made before T; hourly once open\"},", "\t\"be.partitions.maintain\": {},", "every rule says why"),
]
