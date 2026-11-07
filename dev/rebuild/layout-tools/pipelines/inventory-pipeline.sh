#!/bin/bash
# The layout of erp/inventory (layout-plan.md L4), replayable from the branch point. Stops at the first failure.
set -euo pipefail
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad
C=/home/zhijie/Desktop/github/be-assembly-standard/components/erp/inventory
M=$S/mvdecl/mvdecl; G=$S/gobin/goimports; R=$S/restructure/restructure
MOD=github.com/brickKit/erp-inventory/v3
PV3="inventoryv3=github.com/brickKit/erp-inventory/contract/v3/gen/go/be/erp/inventory/v3 orgv3=github.com/brickKit/mdm-org/contract/v3/gen/go/be/mdm/org/v3 productv3=github.com/brickKit/mdm-product/contract/v3/gen/go/be/mdm/product/v3 sdkauthz=github.com/brickKit/be-sdk-go/v3/authz assert=github.com/stretchr/testify/assert require=github.com/stretchr/testify/require"
cd $C
git reset -q --hard HEAD && git clean -qfd internal inventory itest
sed -i 's/  version: 3.0.28/  version: 3.0.29/' component.yaml
sed -i 's/Version  = "3.0.28"/Version  = "3.0.29"/' inventory/definition.go
cd inventory
python3 - <<'EOF'
import pathlib
p = pathlib.Path("definition.go"); s = p.read_text()
old = '\tID       = "erp/inventory"\n'; assert s.count(old) == 1; s = s.replace(old, ""); p.write_text(s)
EOF
python3 $S/splitvars.py lists.go warehouseList positionList movementList lotList serialList
$M module.go core_rules.go errVersion uuidForm scope check invalid notFound quantity change unsupported
$M lists.go core_rules.go filters build
$M module.go masterdata.go legalEntity legalEntityOf product productsOf
$M lists.go warehouses.go listWarehouses warehouseList
$M lists.go stock.go listPositions lotOut listLots serialOut listSerials Positions positionList lotList serialList
$M lists.go receipts.go listMovements movementList
mv lists.go $S/inventory-lists.go.left
$M numbering.go module.go Jobs
$M definition.go core_names.go Product Stream Warehouses DimLegalEntity MaxBatch fields dims Definitions
python3 - <<'EOF'
import pathlib, re
p = pathlib.Path("core_names.go"); s = p.read_text()
s = re.sub(r"^package inventory\n", "package inventory\n\n// ID is the component's ID.\nconst ID = \"erp/inventory\"\n", s, count=1, flags=re.M)
p.write_text(s)
EOF
python3 $S/aliases.py $PV3 -- *.go
$G -w *.go
gofmt -w *.go
go build ./
$R -dir . -map "core_names.go:core,core_rules.go:core,records.go:core,masterdata.go:masterdata,warehouses.go:warehouses,stock.go:stock,receipts.go:movements,numbering.go:numbering,branches.go:branches,issue.go:issue,definition.go:,module.go:,checks.go:,contract_test.go:,checks_integration_test.go:itest,inventory_integration_test.go:itest" -tests -tags integration -entry inventory -apply > $S/inventory-restructure.txt
echo REWRITE-OK
cd $C
mv_() { mkdir -p internal/$2; git mv -f inventory/$1 internal/$2/$3 2>/dev/null || mv inventory/$1 internal/$2/$3; sed -i "s/^package inventory$/package $2/" internal/$2/$3; }
mv_ core_names.go core names.go; mv_ core_rules.go core rules.go; mv_ records.go core records.go
mv_ masterdata.go masterdata masterdata.go; mv_ warehouses.go warehouses warehouses.go; mv_ stock.go stock stock.go
mv_ receipts.go movements movements.go; mv_ numbering.go numbering numbering.go; mv_ branches.go branches branches.go; mv_ issue.go issue issue.go
sed -i 's/\*core\.Base/*Base/g' internal/core/*.go
cp $S/rt-base.go.tmpl internal/core/base.go
A="$PV3"
for p in core masterdata warehouses stock movements numbering branches issue; do A="$A $p=$MOD/internal/$p"; done
python3 $S/aliases.py $A -- inventory/*.go internal/*/*.go
$G -w inventory/*.go internal/*/*.go
go build ./internal/...
echo INTERNAL-OK
cp $S/inventory-module.go inventory/module.go; cp $S/inventory-services.go inventory/services.go
mkdir -p itest
for f in checks inventory; do git mv -f inventory/${f}_integration_test.go itest/${f}_integration_test.go; sed -i "s/^package inventory$/package itest/" itest/${f}_integration_test.go; done
A="$A inventory=$MOD/inventory"
python3 $S/aliases.py $A -- itest/*.go inventory/*.go
$G -w itest/*.go inventory/*.go
python3 - <<'EOF2'
import pathlib, re
for f in ["internal/branches/branches.go", "internal/issue/issue.go", "internal/movements/movements.go"]:
    p = pathlib.Path(f); s = p.read_text()
    s = re.sub(r"stock\.Key\{([^{}:,]+), ([^{}:,]+)\}", r"stock.Key{Product: \1, Warehouse: \2}", s)
    p.write_text(s)
EOF2
go build ./...
go vet ./...
go vet -tags integration ./...
echo PIPELINE-OK
