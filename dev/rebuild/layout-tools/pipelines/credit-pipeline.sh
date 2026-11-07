#!/bin/bash
# The layout of erp/credit (layout-plan.md L4), replayable from the branch point. Stops at the first failure.
set -euo pipefail
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad
C=/home/zhijie/Desktop/github/be-assembly-standard/components/erp/credit
M=$S/mvdecl/mvdecl; G=$S/gobin/goimports; R=$S/restructure/restructure
MOD=github.com/brickKit/erp-credit/v3
PV3="creditv3=github.com/brickKit/erp-credit/contract/v3/gen/go/be/erp/credit/v3 orgv3=github.com/brickKit/mdm-org/contract/v3/gen/go/be/mdm/org/v3 partnerv3=github.com/brickKit/mdm-partner/contract/v3/gen/go/be/mdm/partner/v3 currencyv3=github.com/brickKit/mdm-currency/contract/v3/gen/go/be/mdm/currency/v3"
cd $C
git reset -q --hard HEAD && git clean -qfd internal credit itest
sed -i 's/  version: 3.0.28/  version: 3.0.29/' component.yaml
sed -i 's/Version  = "3.0.28"/Version  = "3.0.29"/' credit/definition.go
cd credit
python3 - <<'EOF'
import pathlib
p = pathlib.Path("definition.go"); s = p.read_text()
old = '\tID       = "erp/credit"\n'; assert s.count(old) == 1; s = s.replace(old, ""); p.write_text(s)
EOF
$M module.go core_rules.go errVersion uuidForm check invalid notFound amount change
$M module.go limits.go unsupported
$M module.go masterdata.go legalEntityActive customerEligible currencyScale
$M branches.go module.go Jobs
$M definition.go core_names.go Partner Stream Limits DimLegalEntity HoldTTL fields Definitions
python3 - <<'EOF'
import pathlib, re
p = pathlib.Path("core_names.go"); s = p.read_text()
s = re.sub(r"^package credit\n", "package credit\n\n// ID is the component's ID.\nconst ID = \"erp/credit\"\n", s, count=1, flags=re.M)
p.write_text(s)
EOF
python3 $S/aliases.py sdkauthz=github.com/brickKit/be-sdk-go/v3/authz $PV3 -- *.go
$G -w *.go
gofmt -w *.go
go build ./
$R -dir . -map "core_names.go:core,core_rules.go:core,records.go:core,masterdata.go:masterdata,limits.go:limits,branches.go:branches,definition.go:,module.go:,checks.go:,contract_test.go:,checks_integration_test.go:itest,credit_integration_test.go:itest" -tests -tags integration -entry credit -apply > $S/credit-restructure.txt
echo REWRITE-OK
cd $C
mv_() { mkdir -p internal/$2; git mv -f credit/$1 internal/$2/$3 2>/dev/null || mv credit/$1 internal/$2/$3; sed -i "s/^package credit$/package $2/" internal/$2/$3; }
mv_ core_names.go core names.go; mv_ core_rules.go core rules.go; mv_ records.go core records.go
mv_ masterdata.go masterdata masterdata.go; mv_ limits.go limits limits.go; mv_ branches.go branches branches.go
sed -i 's/\*core\.Base/*Base/g' internal/core/*.go
cp $S/rt-base.go.tmpl internal/core/base.go
sed -i 's/^func Adjust(m \*core.Base, context.Context, \*creditv3.AdjustRequest)/func Adjust(_ *core.Base, _ context.Context, _ *creditv3.AdjustRequest)/' internal/branches/branches.go
A="sdkauthz=github.com/brickKit/be-sdk-go/v3/authz $PV3"
for p in core masterdata limits branches; do A="$A $p=$MOD/internal/$p"; done
python3 $S/aliases.py $A -- credit/*.go internal/*/*.go
$G -w credit/*.go internal/*/*.go
go build ./internal/...
echo INTERNAL-OK
cp $S/credit-module.go credit/module.go; cp $S/credit-services.go credit/services.go
mkdir -p itest
for f in checks credit; do git mv -f credit/${f}_integration_test.go itest/${f}_integration_test.go; sed -i "s/^package credit$/package itest/" itest/${f}_integration_test.go; done
A="$A credit=$MOD/credit"
python3 $S/aliases.py $A assert=github.com/stretchr/testify/assert require=github.com/stretchr/testify/require -- itest/*.go credit/*.go
$G -w itest/*.go credit/*.go
go build ./...
go vet ./...
go vet -tags integration ./...
echo PIPELINE-OK
