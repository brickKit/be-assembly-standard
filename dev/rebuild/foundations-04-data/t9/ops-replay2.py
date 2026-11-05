TITLE = "(the one that did not build, rewritten) be-ops in progress (item 4 T9d): step 6 (replay: order, calls, alerts, addresses) and 6.8 (keys)"
BUILD = ["go", "vet", "./internal/recovery/"]
TEST = ["go", "test", "-count=1", "./internal/recovery/"]
O, R, S, K, T = "internal/recovery/order.go", "internal/recovery/replay.go", "internal/recovery/replaystep.go", "internal/recovery/keys.go", "internal/recovery/state.go"
MUTANTS = [
    (R, "\tfor deadline := time.Now().Add(wait); !applied; {", "\tfor deadline := time.Now().Add(wait); false && !applied; {", "6.4 is not waited for"),
]
