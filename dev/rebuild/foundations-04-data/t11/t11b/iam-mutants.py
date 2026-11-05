TITLE = "infra/iam-casdoor 3.0.30: 6.7 checks the credential tightenings against Casdoor (P12.20)"
BUILD = ["go", "vet", "-tags", "integration", "./iam/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./iam/"]
F = "iam/replay.go"
MUTANTS = [
    (F, '\tsince := rec.At.Add(-clockSkew)\n', '\tsince := rec.At.Add(-clockSkew - 2*time.Hour)\n', "the record's time bounds Casdoor's change"),
    (F, '\t\tif !notBefore(u.LastChangePasswordTime, since) {', '\t\tif false && !notBefore(u.LastChangePasswordTime, since) {', "a password before the record is inconsistent"),
    (F, '\t\tif u.hasFactors() && !notBefore(u.UpdatedTime, since) {', '\t\tif !notBefore(u.UpdatedTime, since) {', "no factors now is consistent"),
    (F, '\t\tif u.hasFactors() && !notBefore(u.UpdatedTime, since) {', '\t\tif u.hasFactors() && false {', "factors unchanged since the reset are inconsistent"),
    (F, '\t\tif !notBefore(u.UpdatedTime, parseProductTime(seen)) {', '\t\tif false {', "Casdoor older than what was seen is inconsistent"),
    (F, '\t\tif !notBefore(u.UpdatedTime, parseProductTime(seen)) {', '\t\tif notBefore(u.UpdatedTime, parseProductTime(seen)) {', "Casdoor as seen is consistent"),
    (F, '\tif username == "" {\n\t\treturn false, "no such account here", nil', '\tif username == "" {\n\t\treturn true, "no such account here", nil', "no such account is for review"),
    (F, '\tr.Check("credential_tightening", m.checkCredential)\n', '', "the adapter's tightenings are checked"),
    ("iam/product.go", '\treturn u.PreferredMfaType != "" || u.MfaPhoneEnabled || u.MfaEmailEnabled || u.TotpSecret != ""', '\treturn u.PreferredMfaType != "" || u.MfaPhoneEnabled || u.TotpSecret != ""', "an email factor is a factor"),
]
