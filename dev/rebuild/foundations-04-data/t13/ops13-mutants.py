TITLE = "be-ops alpha.13: open-read refuses while no authorization admin is available (RC84)"
BUILD = ["go", "vet", "./internal/recovery/"]
TEST = ["go", "test", "-count=1", "./internal/recovery/"]
MUTANTS = [
    ("internal/recovery/verify.go", "\tif admins.AdminState == \"pending\" {", "\tif admins.AdminState == \"none\" {", "pending is no opening"),
    ("internal/recovery/verifycalls.go", "\t\trep.AdminState, err = c.AdminState(ctx)", "\t\t_, err = c.AdminState(ctx)", "the call reports the state"),
]
