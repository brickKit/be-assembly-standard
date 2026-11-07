#!/bin/bash
# The layout of erp/billing (layout-plan.md L4), replayable from the branch point. Stops at the first failure.
set -euo pipefail
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad
C=/home/zhijie/Desktop/github/be-assembly-standard/components/erp/billing
M=$S/mvdecl/mvdecl; G=$S/gobin/goimports; R=$S/restructure/restructure
MOD=github.com/brickKit/erp-billing/v3
PV3="billingv3=github.com/brickKit/erp-billing/contract/v3/gen/go/be/erp/billing/v3 salesv3=github.com/brickKit/erp-sales/contract/v3/gen/go/be/erp/sales/v3 orgv3=github.com/brickKit/mdm-org/contract/v3/gen/go/be/mdm/org/v3 partnerv3=github.com/brickKit/mdm-partner/contract/v3/gen/go/be/mdm/partner/v3 currencyv3=github.com/brickKit/mdm-currency/contract/v3/gen/go/be/mdm/currency/v3 sdkauthz=github.com/brickKit/be-sdk-go/v3/authz apd=github.com/cockroachdb/apd/v3 assert=github.com/stretchr/testify/assert require=github.com/stretchr/testify/require"
cd $C
git reset -q --hard HEAD && git clean -qfd internal billing itest
sed -i 's/  version: 3.0.37/  version: 3.0.38/' component.yaml
sed -i 's/Version  = "3.0.37"/Version  = "3.0.38"/' billing/definition.go
cd billing
python3 - <<'EOF'
import pathlib
p = pathlib.Path("definition.go"); s = p.read_text()
old = '\tID       = "erp/billing"\n'; assert s.count(old) == 1; s = s.replace(old, ""); p.write_text(s)
EOF
$M module.go core_rules.go errVersion uuidForm check invalid notFound decimal change emit
$M module.go invoices.go purgeDraftKeys
$M issue.go core_rules.go errorsIsNotFound
$M module.go core_names.go jobFormalize
$M definition.go core_names.go Org Stream Invoices DimLegalEntity MaxLines fields Definitions
python3 - <<'EOF'
import pathlib, re
p = pathlib.Path("core_names.go"); s = p.read_text()
s = re.sub(r"^package billing\n", "package billing\n\n// ID is the component's ID.\nconst ID = \"erp/billing\"\n", s, count=1, flags=re.M)
p.write_text(s)
EOF
python3 $S/aliases.py $PV3 -- *.go
$G -w *.go
gofmt -w *.go
go build ./
$R -dir . -map "core_names.go:core,core_rules.go:core,records.go:core,upstream.go:masterdata,invoices.go:invoices,lists.go:invoices,issue.go:issue,print.go:print,print_test.go:print,recoverycheck.go:recoverycheck,definition.go:,module.go:,checks.go:,contract_test.go:,checks_integration_test.go:itest,billing_integration_test.go:itest,standins_integration_test.go:itest" -rename invoice=readInvoice -tests -tags integration -entry billing -apply > $S/billing-restructure.txt
echo REWRITE-OK
cd $C
mv_() { mkdir -p internal/$2; git mv -f billing/$1 internal/$2/$3 2>/dev/null || mv billing/$1 internal/$2/$3; sed -i "s/^package billing$/package $2/" internal/$2/$3; }
mv_ core_names.go core names.go; mv_ core_rules.go core rules.go; mv_ records.go core records.go
mv_ upstream.go masterdata masterdata.go; mv_ invoices.go invoices invoices.go; mv_ lists.go invoices lists.go
mv_ issue.go issue issue.go; mv_ print.go print print.go; mv_ print_test.go print print_test.go; mv_ recoverycheck.go recoverycheck recoverycheck.go
sed -i 's/\*core\.Base/*Base/g' internal/core/*.go
cp $S/rt-base.go.tmpl internal/core/base.go
A="$PV3"
for p in core masterdata invoices issue print recoverycheck; do A="$A $p=$MOD/internal/$p"; done
python3 $S/aliases.py $A -- billing/*.go internal/*/*.go
$G -w billing/*.go internal/*/*.go
cat $S/billing-corrections.go.part >> internal/invoices/invoices.go
sed -i 's/\bTime_(/time_(/g' internal/print/print_test.go
$G -w internal/invoices/invoices.go
go build ./internal/...
echo INTERNAL-OK
cp $S/billing-module.go billing/module.go; cp $S/billing-services.go billing/services.go
sed -i 's/^\t\tRun: m.claimsCheck}); err != nil {$/\t\tRun: func(ctx context.Context, read recovery.Read) (recovery.Result, error) {\n\t\t\treturn recoverycheck.ClaimsCheck(m.b, ctx, read)\n\t\t}}); err != nil {/' billing/checks.go
mkdir -p itest
for f in checks billing standins; do git mv -f billing/${f}_integration_test.go itest/${f}_integration_test.go; sed -i "s/^package billing$/package itest/" itest/${f}_integration_test.go; done
sed -i 's/\bprint\.Time_(/time_(/g' billing/contract_test.go
printf '\n// time_ reads an RFC 3339 time (as the print view model takes them).\nfunc time_(s string) (time.Time, error) { return time.Parse(time.RFC3339Nano, s) }\n' >> billing/contract_test.go
A="$A billing=$MOD/billing"
python3 $S/aliases.py $A -- itest/*.go billing/*.go
$G -w itest/*.go billing/*.go
go build ./...
go vet ./...
go vet -tags integration ./...
echo PIPELINE-OK
