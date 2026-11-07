#!/bin/bash
# The layout of mdm/product (layout-plan.md L4), replayable from the branch point. Stops at the first failure.
set -euo pipefail
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad
C=/home/zhijie/Desktop/github/be-assembly-standard/components/mdm/product
M=$S/mvdecl/mvdecl; G=$S/gobin/goimports; R=$S/restructure/restructure
MOD=github.com/brickKit/mdm-product/v3
PV3="productv3=github.com/brickKit/mdm-product/contract/v3/gen/go/be/mdm/product/v3 orgv3=github.com/brickKit/mdm-org/contract/v3/gen/go/be/mdm/org/v3"
cd $C
git reset -q --hard HEAD && git clean -qfd internal product itest
sed -i 's/  version: 3.0.31/  version: 3.0.32/' component.yaml
sed -i 's/Version  = "3.0.31"/Version  = "3.0.32"/' product/definition.go
cd product
python3 - <<'EOF'
import pathlib
p = pathlib.Path("definition.go"); s = p.read_text()
for old in ['\tID       = "mdm/product"\n', '\n\tOrg = "mdm/org"\n']:
    assert s.count(old) == 1, old; s = s.replace(old, "\n" if old.startswith("\n") else "")
p.write_text(s)
EOF
python3 - <<'EOF2'
import pathlib
p = pathlib.Path("lists.go"); s = p.read_text()
old = "\tcategoryList = list.Spec"
assert s.count(old) == 1
s = s.replace("var (\n\tproductList = list.Spec", "var productList = list.Spec").replace(
    "Fields: []string{\"code\", \"name\", \"names\"}}}}\n\tcategoryList = list.Spec", "Fields: []string{\"code\", \"name\", \"names\"}}}}\n\nvar categoryList = list.Spec")
s = s.replace("Kind: list.Text, Sortable: true}}}\n)\n", "Kind: list.Text, Sortable: true}}}\n")
p.write_text(s)
EOF2
$M module.go core_rules.go errVersion codeForm check invalid notFound change same checkNames unsupported
$M units.go core_rules.go decimal canonical sortAvailability
$M module.go products.go searchOf productIn apply write createProduct product getProduct changeProduct updateProduct productState legalEntityActive putAvailability
$M lists.go products.go listProducts productList
$M source.go products.go Eligibility eligibility eligibilityHTTP
$M lists.go categories.go listCategories categoryList
mv lists.go $S/product-lists.go.left
$M definition.go core_names.go Stream Products MaxBatch Definitions
python3 - <<'EOF'
import pathlib, re
p = pathlib.Path("core_names.go"); s = p.read_text()
s = re.sub(r"^package product\n", "package product\n\n// ID is the component's ID; Org is the dependency availability checks legal entities with.\nconst (\n\tID  = \"mdm/product\"\n\tOrg = \"mdm/org\"\n)\n", s, count=1, flags=re.M)
p.write_text(s)
EOF
python3 $S/aliases.py sdkauthz=github.com/brickKit/be-sdk-go/v3/authz apd=github.com/cockroachdb/apd/v3 $PV3 -- *.go
$G -w *.go
gofmt -w *.go
go build ./
$R -dir . -map "core_names.go:core,core_rules.go:core,records.go:core,products.go:products,categories.go:categories,units.go:units,source.go:source,definition.go:,module.go:,checks.go:,contract_test.go:,checks_integration_test.go:itest,product_integration_test.go:itest" -rename eligibility=eligibilityOf -tests -tags integration -entry product -apply > $S/product-restructure.txt
echo REWRITE-OK
cd $C
mv_() { mkdir -p internal/$2; git mv -f product/$1 internal/$2/$3 2>/dev/null || mv product/$1 internal/$2/$3; sed -i "s/^package product$/package $2/" internal/$2/$3; }
mv_ core_names.go core names.go; mv_ core_rules.go core rules.go; mv_ records.go core records.go
mv_ products.go products products.go; mv_ categories.go categories categories.go; mv_ units.go units units.go; mv_ source.go source source.go
sed -i 's/\*core\.Base/*Base/g' internal/core/*.go
cp $S/currency-base.go.tmpl internal/core/base.go
sed -i 's/m\.instance/m.Instance/g; s/m\.deployment/m.Deployment/g' internal/source/source.go
A="sdkauthz=github.com/brickKit/be-sdk-go/v3/authz apd=github.com/cockroachdb/apd/v3 $PV3"
for p in core products categories units source; do A="$A $p=$MOD/internal/$p"; done
python3 $S/aliases.py $A -- product/*.go internal/*/*.go
$G -w product/*.go internal/*/*.go
go build ./internal/...
echo INTERNAL-OK
cp $S/product-module.go product/module.go; cp $S/product-services.go product/services.go
mkdir -p itest
for f in checks product; do git mv -f product/${f}_integration_test.go itest/${f}_integration_test.go; sed -i "s/^package product$/package itest/" itest/${f}_integration_test.go; done
A="$A product=$MOD/product"
python3 $S/aliases.py $A assert=github.com/stretchr/testify/assert require=github.com/stretchr/testify/require -- itest/*.go product/*.go
$G -w itest/*.go product/*.go
go build ./...
go vet ./...
go vet -tags integration ./...
echo PIPELINE-OK
