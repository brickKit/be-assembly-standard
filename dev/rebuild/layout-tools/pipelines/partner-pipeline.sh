#!/bin/bash
# The layout of mdm/partner (layout-plan.md L4), replayable from the branch point. Stops at the first failure.
set -euo pipefail
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad
C=/home/zhijie/Desktop/github/be-assembly-standard/components/mdm/partner
M=$S/mvdecl/mvdecl; G=$S/gobin/goimports; R=$S/restructure/restructure
MOD=github.com/brickKit/mdm-partner/v3
PV3=partnerv3=github.com/brickKit/mdm-partner/contract/v3/gen/go/be/mdm/partner/v3
cd $C
git reset -q --hard HEAD && git clean -qfd internal partner itest
sed -i 's/  version: 3.0.32/  version: 3.0.33/' component.yaml
sed -i 's/Version  = "3.0.32"/Version  = "3.0.33"/' partner/definition.go
cd partner
python3 - <<'EOF'
import pathlib
p = pathlib.Path("definition.go"); s = p.read_text()
for old in ['\tID       = "mdm/partner"\n', '\n\tOrg = "mdm/org"\n']:
    assert s.count(old) == 1, old; s = s.replace(old, "\n" if old.startswith("\n") else "")
p.write_text(s)
EOF
$M module.go core_rules.go errVersion uuidForm check invalid notFound change same unsupported
$M module.go partners.go searchOf partnerIn apply answer createPartner answerWith partner getPartner changePartner updatePartner partnerState checkCurrency
$M lists.go partners.go partnerList listPartners
mv lists.go $S/partner-lists.go.left
$M definition.go core_names.go Stream Partners MaxBatch Definitions
python3 - <<'EOF'
import pathlib, re
p = pathlib.Path("core_names.go"); s = p.read_text()
s = re.sub(r"^package partner\n", "package partner\n\n// ID is the component's ID; Org is the dependency the roles check legal entities with.\nconst (\n\tID  = \"mdm/partner\"\n\tOrg = \"mdm/org\"\n)\n", s, count=1, flags=re.M)
p.write_text(s)
EOF
python3 $S/aliases.py sdkauthz=github.com/brickKit/be-sdk-go/v3/authz $PV3 -- *.go
$G -w *.go
gofmt -w *.go
go build ./
$R -dir . -map "core_names.go:core,core_rules.go:core,records.go:core,partners.go:partners,roles.go:roles,source.go:source,definition.go:,module.go:,checks.go:,contract_test.go:,checks_integration_test.go:itest,partner_integration_test.go:itest" -rename eligibility=eligibilityOf -tests -tags integration -entry partner -apply > $S/partner-restructure.txt
echo REWRITE-OK
cd $C
mv_() { mkdir -p internal/$2; git mv -f partner/$1 internal/$2/$3 2>/dev/null || mv partner/$1 internal/$2/$3; sed -i "s/^package partner$/package $2/" internal/$2/$3; }
mv_ core_names.go core names.go; mv_ core_rules.go core rules.go; mv_ records.go core records.go
mv_ partners.go partners partners.go; mv_ roles.go roles roles.go; mv_ source.go source source.go
sed -i 's/\*core\.Base/*Base/g' internal/core/*.go
cp $S/currency-base.go.tmpl internal/core/base.go
sed -i 's/m\.instance/m.Instance/g; s/m\.deployment/m.Deployment/g' internal/source/source.go
A="sdkauthz=github.com/brickKit/be-sdk-go/v3/authz $PV3"
for p in core partners roles source; do A="$A $p=$MOD/internal/$p"; done
python3 $S/aliases.py $A -- partner/*.go internal/*/*.go
$G -w partner/*.go internal/*/*.go
go build ./internal/...
echo INTERNAL-OK
cp $S/partner-module.go partner/module.go; cp $S/partner-services.go partner/services.go
mkdir -p itest
for f in checks partner; do git mv -f partner/${f}_integration_test.go itest/${f}_integration_test.go; sed -i "s/^package partner$/package itest/" itest/${f}_integration_test.go; done
A="$A partner=$MOD/partner"
python3 $S/aliases.py $A assert=github.com/stretchr/testify/assert require=github.com/stretchr/testify/require -- itest/*.go partner/*.go
$G -w itest/*.go partner/*.go
go build ./...
go vet ./...
go vet -tags integration ./...
echo PIPELINE-OK
