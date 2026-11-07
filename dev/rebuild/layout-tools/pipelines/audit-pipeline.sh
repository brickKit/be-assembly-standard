#!/bin/bash
# The layout of infra/audit (layout-plan.md L4), replayable from the branch point. Stops at the first failure.
set -euo pipefail
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad
C=/home/zhijie/Desktop/github/be-assembly-standard/components/infra/audit
M=$S/mvdecl/mvdecl; G=$S/gobin/goimports; R=$S/restructure/restructure
MOD=github.com/brickKit/infra-audit/v3
PV3="auditv3=github.com/brickKit/infra-audit/contract/v3/gen/go/be/audit/v3"
cd $C
git reset -q --hard HEAD && git clean -qfd internal audit itest
sed -i 's/  version: 3.0.33/  version: 3.0.34/' component.yaml
cd audit
python3 - <<'EOF'
import pathlib
p = pathlib.Path("audit.go"); s = p.read_text()
for old in ['\tVersion     = "3.0.33"\n', '\tGRPCPort    = 9206\n']:
    assert s.count(old) == 1, old; s = s.replace(old, "")
p.write_text(s)
EOF
$M audit.go definition.go Keys migrationFiles migrations Definition
python3 - <<'EOF'
import pathlib, re
p = pathlib.Path("definition.go"); s = p.read_text()
s = re.sub(r"^package audit\n", "package audit\n\n// The component's version and its system port.\nconst (\n\tVersion  = \"3.0.34\"\n\tGRPCPort = 9206\n)\n", s, count=1, flags=re.M)
p.write_text(s)
EOF
$M audit.go core_names.go ID Definitions
python3 - <<'EOF2'
import pathlib
p = pathlib.Path("tiering.go"); s = p.read_text()
for old in ['\tOpHold          = "infra.audit.record.hold"\n', '\tOpApproveDelete = "infra.audit.record.approve_destruction"\n']:
    assert s.count(old) == 1, old; s = s.replace(old, "")
p.write_text(s)
p = pathlib.Path("core_names.go"); s = p.read_text()
s = s.replace("\n// Definitions", "\n// The audit records' holds and deletion approvals (assembly protocol 11), declared on the records resource.\nconst (\n\tOpHold          = \"infra.audit.record.hold\"\n\tOpApproveDelete = \"infra.audit.record.approve_destruction\"\n)\n\n// Definitions", 1)
p.write_text(s)
EOF2
$M audit.go core_rules.go epochOf chainNext
$M records.go core_rules.go recordSkew position parsePosition
$M audit.go intake.go Submit item Watermark
$M audit.go records.go query
$M chain.go audit.go Jobs
$M audit_test.go core_test.go TestChainOverDigests
git mv -f recovery.go checks.go 2>/dev/null || mv recovery.go checks.go
python3 $S/aliases.py sdkauthz=github.com/brickKit/be-sdk-go/v3/authz $PV3 assert=github.com/stretchr/testify/assert require=github.com/stretchr/testify/require -- *.go
$G -w *.go
gofmt -w *.go
go build ./
go vet -tags integration ./ >/dev/null
$R -dir . -map "core_names.go:core,core_rules.go:core,core_test.go:core,intake.go:intake,chain.go:chain,evidence.go:evidence,categories_test.go:evidence,records.go:reading,tiering.go:archive,definition.go:,audit.go:,checks.go:,audit_test.go:,manifest_test.go:,audit_integration_test.go:itest,evidence_integration_test.go:itest,tiering_integration_test.go:itest" -tests -tags integration -entry audit -apply > $S/audit-restructure.txt
echo REWRITE-OK
cd $C
mv_() { mkdir -p internal/$2; git mv -f audit/$1 internal/$2/$3 2>/dev/null || mv audit/$1 internal/$2/$3; sed -i "s/^package audit$/package $2/" internal/$2/$3; }
mv_ core_names.go core names.go; mv_ core_rules.go core rules.go; mv_ core_test.go core rules_test.go
mv_ intake.go intake intake.go; mv_ chain.go chain chain.go; mv_ evidence.go evidence evidence.go; mv_ categories_test.go evidence evidence_test.go
mv_ records.go reading reading.go; mv_ tiering.go archive archive.go
sed -i 's/\*core\.Base/*Base/g' internal/core/*.go
cp $S/rt-base.go.tmpl internal/core/base.go
sed -i 's/^\tM \*Module `json:"-"`$/\tM *core.Base/' internal/reading/reading.go
A="sdkauthz=github.com/brickKit/be-sdk-go/v3/authz $PV3 assert=github.com/stretchr/testify/assert require=github.com/stretchr/testify/require"
for p in core intake chain evidence reading archive; do A="$A $p=$MOD/internal/$p"; done
python3 $S/aliases.py $A -- audit/*.go internal/*/*.go
$G -w audit/*.go internal/*/*.go
go build ./internal/...
echo INTERNAL-OK
git rm -qf audit/audit.go
cp $S/audit-module.go audit/module.go; cp $S/audit-services.go audit/services.go
sed -i 's/^\t\t\tm := &Module{rt: rt}$/\t\t\tm := \&Module{b: \&core.Base{RT: rt}}/' audit/definition.go
mkdir -p itest
for f in audit evidence tiering; do git mv -f audit/${f}_integration_test.go itest/${f}_integration_test.go; sed -i "s/^package audit$/package itest/" itest/${f}_integration_test.go; done
A="$A audit=$MOD/audit"
python3 $S/aliases.py $A -- itest/*.go audit/*.go
$G -w itest/*.go audit/*.go
go build ./...
go vet ./...
go vet -tags integration ./...
echo PIPELINE-OK
