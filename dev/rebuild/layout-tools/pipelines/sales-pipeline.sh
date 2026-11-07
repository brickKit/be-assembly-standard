#!/bin/bash
# The layout pilot on erp/sales (layout-plan.md L1), replayable from the repository's HEAD: pre-split, the type-aware
# rewrite, the move into internal/ packages. Stops at the first failure.
set -euo pipefail
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad
C=/home/zhijie/Desktop/github/be-assembly-standard/components/erp/sales
M=$S/mvdecl/mvdecl; G=$S/gobin/goimports; R=$S/restructure/restructure
MOD=github.com/brickKit/erp-sales/v3
cd $C
git reset -q --hard HEAD && git clean -qfd internal sales itest
sed -i 's/  version: 3.0.38/  version: 3.0.39/' component.yaml
sed -i 's/Version  = "3.0.38"/Version  = "3.0.39"/' sales/definition.go
cd sales
# 1. pre-split: each declaration into the file of the package it goes to
python3 - <<'EOF'
import pathlib
p = pathlib.Path("lists.go"); s = p.read_text()
s = s.replace("var (\n\tnumberCustomer", "var numberCustomer").replace("Fields: []string{\"number\", \"customer\"}}}\n\tquotationList  =", "Fields: []string{\"number\", \"customer\"}}}\n\nvar quotationList =")
s = s.replace("Search: numberCustomer}\n\torderList =", "Search: numberCustomer}\n\nvar orderList =")
s = s.replace("Filterable: true})}\n\tdeliveryList =", "Filterable: true})}\n\nvar deliveryList =")
s = s.replace("Filterable: true}}}\n\tnewestFirst = []list.Order{{Field: \"created_at\", Desc: true}}\n)", "Filterable: true}}}\n\nvar newestFirst = []list.Order{{Field: \"created_at\", Desc: true}}")
p.write_text(s)
EOF
$M lists.go quotations.go listQuotations quotationList
$M lists.go orders.go orderFromAll orderFrom listOrders orderList
$M lists.go delivery.go listDeliveries deliveryList
$M lists.go documents.go docColumns filters build docParams numberCustomer newestFirst
mv lists.go $S/lists.go.left
$M advance.go orders.go setOrderState
$M module.go orders.go unsupportedOnOrder
$M billing.go ledger.go ledgerFacts
$M module.go core_rules.go errVersion uuidForm docFacts check invalid notFound decimal change emit
$M definition.go core_names.go Partner Stream Quotations DimLegalEntity SyncBudget fields scoped documentFields Definitions
$M lines.go core_rules.go times
python3 - <<'EOF'
import pathlib, re
p = pathlib.Path("definition.go"); s = p.read_text()
s = s.replace('\tID       = "erp/sales"\n', ""); p.write_text(s)
p = pathlib.Path("core_names.go"); s = p.read_text()
s = s.replace("\npackage sales\n", "\npackage sales\n", 1)
s = re.sub(r"^package sales\n", "package sales\n\n// ID is the component's ID.\nconst ID = \"erp/sales\"\n", s, count=1, flags=re.M)
o = '\tOpSysBilling = "erp.sales.system.billing"\n'
s = s.replace(o, o + '\t// the archived orders (assembly protocol 11): holds, deletion approvals, the destructions\' replay\n'
              '\tOpOrderHold    = "erp.sales.system.order_hold"\n\tOpOrderDestroy = "erp.sales.system.order_destruction"\n'
              '\tOpReplay       = "erp.sales.system.replay"\n')
p.write_text(s)
p = pathlib.Path("tiering.go"); s = p.read_text()
for k in ["\tOpOrderHold       = \"erp.sales.system.order_hold\"\n", "\tOpOrderDestroy    = \"erp.sales.system.order_destruction\"\n",
          "\tOpReplay          = \"erp.sales.system.replay\"\n"]:
    assert s.count(k) == 1, k
    s = s.replace(k, "")
p.write_text(s)
EOF
python3 $S/aliases.py sdkauthz=github.com/brickKit/be-sdk-go/v3/authz apd=github.com/cockroachdb/apd/v3 -- *.go
$G -w *.go
gofmt -w *.go
go build ./
# 2. the type-aware rewrite
$R -dir . -map "$(cat $S/sales-map.txt)" -rename process=readProcess -tests -tags integration -entry sales -apply > $S/restructure-apply.txt
# 3. into internal/ packages
cd $C
mv_() { mkdir -p internal/$2; git mv -f sales/$1 internal/$2/$3 2>/dev/null || mv sales/$1 internal/$2/$3; sed -i "s/^package sales$/package $2/" internal/$2/$3; }
mv_ core_names.go core names.go; mv_ core_rules.go core rules.go; mv_ records.go core records.go
mv_ upstream.go masterdata upstream.go; mv_ orgunits.go orgunits orgunits.go; mv_ pricing.go pricing pricing.go
mv_ documents.go documents documents.go; mv_ lines.go documents lines.go
mv_ orders.go orders orders.go; mv_ tiering.go orders archive.go; mv_ quotations.go quotations quotations.go
mv_ ledger.go ledger ledger.go; mv_ confirmation.go confirmations confirmation.go; mv_ advance.go confirmations advance.go
mv_ cancel.go confirmations cancel.go; mv_ delivery.go deliveries delivery.go; mv_ billing.go billingsource billing.go
mv_ recoverycheck.go recoverycheck recoverycheck.go
sed -i 's/\*core\.Base/*Base/g' internal/core/*.go
cat > internal/core/base.go <<'EOF'
package core

import "github.com/brickKit/be-sdk-go/v3/runtime"

// Base is what every module works with: the component's runtime (its database, calls, events, audit, logger).
type Base struct {
	RT *runtime.Runtime
}
EOF
sed -i 's/^func Reverse(m \*core.Base, context.Context, \*salesv3.ReverseRequest)/func Reverse(_ *core.Base, _ context.Context, _ *salesv3.ReverseRequest)/' internal/billingsource/billing.go
sed -i 's/^type orgSource struct{ m \*Module }/type orgSource struct{ m *core.Base }/' internal/orgunits/orgunits.go
A="apd=github.com/cockroachdb/apd/v3 sdkauthz=github.com/brickKit/be-sdk-go/v3/authz salesv3=github.com/brickKit/erp-sales/contract/v3/gen/go/be/erp/sales/v3"
for p in core masterdata orgunits pricing documents orders quotations ledger confirmations deliveries billingsource recoverycheck; do A="$A $p=$MOD/internal/$p"; done
python3 $S/aliases.py $A -- sales/*.go internal/*/*.go
$G -w sales/*.go internal/*/*.go
go build ./internal/...
# 4. the entry's assembly (written by hand once, kept beside this script)
cp $S/sales-module.go sales/module.go; cp $S/sales-checks.go sales/checks.go; cp $S/sales-services.go sales/services.go
# 5. the integration tests into itest/
mkdir -p itest
for f in checks flows sales standins tiering; do git mv -f sales/${f}_integration_test.go itest/${f}_integration_test.go; sed -i "s/^package sales$/package itest/" itest/${f}_integration_test.go; done
A="$A sales=$MOD/sales"
python3 $S/aliases.py $A -- itest/*.go sales/definition.go sales/contract_test.go
$G -w itest/*.go sales/*.go
sed -i 's/core.Measure{"0", "0"}/core.Measure{Quantity: "0", Amount: "0"}/g' sales/contract_test.go
go build ./...
go vet ./...
go vet -tags integration ./...
echo PIPELINE-OK
# 6. one integration test file per business flow
cd $C/itest
for pair in pricingAndQuotations:quotations confirmations:confirmations deliveries:deliveries billingSource:billingsource lists:lists departments,laterOrgEvents:orgunits outbox:outbox; do
  steps=${pair%%:*}; file=${pair##*:}_integration_test.go
  $M flows_integration_test.go $file ${steps//,/ }
  sed -i '1s/^/\/\/go:build integration\n\n/' $file
done
git rm -qf flows_integration_test.go  # what is left: the file comment, now in itest/AGENTS.md
git mv -f checks_integration_test.go recoverycheck_integration_test.go
git mv -f tiering_integration_test.go archive_integration_test.go
git mv -f sales_integration_test.go endtoend_integration_test.go
python3 $S/aliases.py $A $(cat $S/itest-aliases.clean) assert=github.com/stretchr/testify/assert require=github.com/stretchr/testify/require -- *.go
$G -w *.go
cd $C
go vet -tags integration ./itest/
echo SPLIT-OK
