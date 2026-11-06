TITLE = "be-sdk-go alpha.102: the writer is the signer (P12.4)"
BUILD = ["go", "vet", "-tags", "integration", "./runprofile/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/compenv.sh && go test -count=1 -tags integration ./runprofile/"]
MUTANTS = [
    ("runprofile/runprofile.go", "\tif err := writerIsSigner(r, leaf); err != nil {\n\t\treturn err\n\t}\n\tmsg, err := SignedBytes(r)", "\tmsg, err := SignedBytes(r)", "Verify (the current trust root) checks the writer"),
    ("runprofile/runprofile.go", "\tif err := writerIsSigner(r, leaf); err != nil {\n\t\treturn err\n\t}\n\treturn verifySignature(r, leaf)", "\treturn verifySignature(r, leaf)", "the history's verification checks the writer"),
    ("runprofile/runprofile.go", "\t\tif u.String() == want {", "\t\tif strings.HasSuffix(u.String(), \"/component/\"+r.Writer.Component) || u.String() == want {", "the deployment is part of the identity"),
]
