TITLE = "mdm/employee E3e: account links"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
# the checks made twice on purpose (before the authorization member is asked, and again under the lock; the in-
# transaction check and the unique index) are not mutated one at a time: each alone is equivalent
MUTANTS = [
    ("internal/links/links.go", "\tif handled, err := check(m, c, ctx, emp.ID, emp.Version, in.Account, \"link\", actor, in.Confirmation); handled || err != nil {",
     "\tif handled, err := check(m, c, ctx, emp.ID, emp.Version, in.Account, \"link\", actor, in.Confirmation); false && (handled || err != nil) {",
     "a link needs the authorization member's confirmation"),
    ("internal/links/links.go", "check(m, c, ctx, emp.ID, emp.Version, l.Account, \"unlink\", actor, in.Confirmation)",
     "check(m, c, ctx, emp.ID, emp.Version, l.Account, \"link\", actor, in.Confirmation)", "the end of a link is asked as an unlink"),
    ("employee/module.go", "\tb.AdminWarning = links.AdminWarning(b)\n", "", "a termination warns about a linked admin"),
    ("internal/links/links.go", "\treturn len(out.GetAdministrators()) > 0, nil", "\treturn len(out.GetAdministrators()) > 99, nil", "the warning follows the authorization member's admins"),
    ("internal/links/links.go", "\tcase authzv3.AccountChangeVerdict_ACCOUNT_CHANGE_VERDICT_UNPROVABLE: // security 03: nothing decided, ask again later\n",
     "\tcase -1:\n", "unprovable is processing, not a refusal"),
]
