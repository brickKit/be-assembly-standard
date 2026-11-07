#!/bin/bash
# The layout of mdm/currency (layout-plan.md L4), replayable from the branch point: pre-split, the type-aware rewrite,
# the move into internal/ packages. Stops at the first failure.
set -euo pipefail
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad
C=/home/zhijie/Desktop/github/be-assembly-standard/components/mdm/currency
M=$S/mvdecl/mvdecl; G=$S/gobin/goimports; R=$S/restructure/restructure
MOD=github.com/brickKit/mdm-currency/v3
cd $C
git reset -q --hard HEAD && git clean -qfd internal currency itest
sed -i 's/  version: 3.0.28/  version: 3.0.29/' component.yaml
sed -i 's/Version  = "3.0.28"/Version  = "3.0.29"/' currency/definition.go
cd currency
# 1. pre-split: each declaration into the file of the package it goes to
python3 - <<'EOF'
import pathlib
p = pathlib.Path("lists.go"); s = p.read_text()
i = s.index("var (\n\tcurrencyList"); j = s.index("\n)\n", i)
block = s[i + len("var (\n"):j]
decls = []
for part in block.split("\n\t"):
    pass
# each spec starts at a line "\t<name> = list.Spec" or "\t<name>     = list.Spec"
import re
names = [m.start() for m in re.finditer(r"^\t\w+\s+= list\.Spec", block, re.M)]
pieces = [block[a:b] for a, b in zip(names, names[1:] + [len(block)])]
out = "\n\n".join("var " + re.sub(r"^\t(\w+)\s+=", r"\1 =", pc.strip("\n"), count=1).replace("\n\t", "\n") for pc in pieces)
s = s[:i] + out + s[j + 2:]
p.write_text(s)
p = pathlib.Path("definition.go"); s = p.read_text()
old = '\tID       = "mdm/currency"\n'; assert s.count(old) == 1; s = s.replace(old, ""); p.write_text(s)
EOF
$M module.go core_rules.go errVersion isoCode check invalid notFound change checkNames sameNames positive checkPair
$M lists.go core_rules.go build eq
$M module.go currencies.go getCurrency currencyPatch updateCurrency sameCurrency currencySearch
$M lists.go currencies.go listCurrencies currencyList
$M source.go currencies.go backfill
$M module.go rates.go rateTypeIn putRateType rateIn putRate effectiveHTTP effective
$M lists.go rates.go listRateTypes listRates rateTypeList rateList
$M source.go module.go Jobs
$M definition.go core_names.go Stream Currencies MaxBatch Definitions
mv lists.go $S/currency-lists.go.left
python3 - <<'EOF'
import pathlib, re
p = pathlib.Path("core_names.go"); s = p.read_text()
s = re.sub(r"^package currency\n", "package currency\n\n// ID is the component's ID.\nconst ID = \"mdm/currency\"\n", s, count=1, flags=re.M)
p.write_text(s)
EOF
python3 $S/aliases.py sdkauthz=github.com/brickKit/be-sdk-go/v3/authz currencyv3=github.com/brickKit/mdm-currency/contract/v3/gen/go/be/mdm/currency/v3 -- *.go
$G -w *.go
gofmt -w *.go
go build ./
# 2. the type-aware rewrite
$R -dir . -map "core_names.go:core,core_rules.go:core,records.go:core,currencies.go:currencies,rates.go:rates,source.go:source,definition.go:,module.go:,checks.go:,contract_test.go:,checks_integration_test.go:itest,currency_integration_test.go:itest" -tests -tags integration -entry currency -apply > $S/currency-restructure.txt
echo REWRITE-OK
# 3. into internal/ packages
cd $C
mv_() { mkdir -p internal/$2; git mv -f currency/$1 internal/$2/$3 2>/dev/null || mv currency/$1 internal/$2/$3; sed -i "s/^package currency$/package $2/" internal/$2/$3; }
mv_ core_names.go core names.go; mv_ core_rules.go core rules.go; mv_ records.go core records.go
mv_ currencies.go currencies currencies.go; mv_ rates.go rates rates.go; mv_ source.go source source.go
sed -i 's/\*core\.Base/*Base/g' internal/core/*.go
cat > internal/core/base.go <<'EOF'
package core

import "github.com/brickKit/be-sdk-go/v3/runtime"

// Base is what every module works with: the component's runtime (its database, events, audit, logger), and the
// deployment and implementation instance the source methods stamp their answers with (protocol 02).
type Base struct {
	RT         *runtime.Runtime
	Deployment string
	Instance   string
}
EOF
sed -i 's/m\.instance/m.Instance/g; s/m\.deployment/m.Deployment/g' internal/source/source.go
A="sdkauthz=github.com/brickKit/be-sdk-go/v3/authz currencyv3=github.com/brickKit/mdm-currency/contract/v3/gen/go/be/mdm/currency/v3"
for p in core currencies rates source; do A="$A $p=$MOD/internal/$p"; done
python3 $S/aliases.py $A -- currency/*.go internal/*/*.go
$G -w currency/*.go internal/*/*.go
go build ./internal/...
# 4. the entry's assembly (written by hand once, kept beside this script)
cp $S/currency-module.go currency/module.go; cp $S/currency-services.go currency/services.go
# 5. the integration tests into itest/; the unit test of a core rule into core
mkdir -p itest
for f in checks currency; do git mv -f currency/${f}_integration_test.go itest/${f}_integration_test.go; sed -i "s/^package currency$/package itest/" itest/${f}_integration_test.go; done
A="$A currency=$MOD/currency"
python3 $S/aliases.py $A assert=github.com/stretchr/testify/assert require=github.com/stretchr/testify/require -- itest/*.go currency/*.go
$G -w itest/*.go currency/*.go
go build ./...
go vet ./...
go vet -tags integration ./...
echo PIPELINE-OK
