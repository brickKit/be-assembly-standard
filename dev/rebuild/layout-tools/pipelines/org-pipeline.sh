#!/bin/bash
# The layout of mdm/org (layout-plan.md L4), replayable from the branch point. Stops at the first failure.
set -euo pipefail
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad
C=/home/zhijie/Desktop/github/be-assembly-standard/components/mdm/org
M=$S/mvdecl/mvdecl; G=$S/gobin/goimports; R=$S/restructure/restructure
MOD=github.com/brickKit/mdm-org/v3
PV3="orgv3=github.com/brickKit/mdm-org/contract/v3/gen/go/be/mdm/org/v3"
cd $C
git reset -q --hard HEAD && git clean -qfd internal org itest
sed -i 's/  version: 3.0.29/  version: 3.0.30/' component.yaml
sed -i 's/Version  = "3.0.29"/Version  = "3.0.30"/' org/definition.go
cd org
python3 - <<'EOF'
import pathlib
p = pathlib.Path("definition.go"); s = p.read_text()
old = '\tID       = "mdm/org"\n'; assert s.count(old) == 1; s = s.replace(old, ""); p.write_text(s)
EOF
$M module.go core_rules.go errVersion codeForm check invalid notFound change checkNames searchOf same unsupported
python3 $S/splitvars.py lists.go entityList unitList
$M lists.go core_rules.go build eq
$M module.go entities.go entityIn validate createEntity getEntity entity updateEntity entityState updateEntityWith businessDate writeEntity
$M lists.go entities.go listEntities entityList
$M lists.go units.go listUnits unitList
mv lists.go $S/org-lists.go.left
$M module.go source.go CatchUp
$M replay.go module.go Replays
$M definition.go core_names.go Stream LegalEntities MaxBatch Definitions
python3 - <<'EOF'
import pathlib, re
p = pathlib.Path("core_names.go"); s = p.read_text()
s = re.sub(r"^package org\n", "package org\n\n// ID is the component's ID.\nconst ID = \"mdm/org\"\n", s, count=1, flags=re.M)
p.write_text(s)
EOF
python3 $S/aliases.py sdkauthz=github.com/brickKit/be-sdk-go/v3/authz $PV3 -- *.go
$G -w *.go
gofmt -w *.go
go build ./
$R -dir . -map "core_names.go:core,core_rules.go:core,records.go:core,entities.go:entities,units.go:units,evidence.go:tightening,replay.go:replay,source.go:source,definition.go:,module.go:,checks.go:,contract_test.go:,checks_integration_test.go:itest,org_integration_test.go:itest,evidence_integration_test.go:itest" -tests -tags integration -entry org -apply > $S/org-restructure.txt
echo REWRITE-OK
cd $C
mv_() { mkdir -p internal/$2; git mv -f org/$1 internal/$2/$3 2>/dev/null || mv org/$1 internal/$2/$3; sed -i "s/^package org$/package $2/" internal/$2/$3; }
mv_ core_names.go core names.go; mv_ core_rules.go core rules.go; mv_ records.go core records.go
mv_ entities.go entities entities.go; mv_ units.go units units.go; mv_ evidence.go tightening tightening.go
mv_ replay.go replay replay.go; mv_ source.go source source.go
sed -i 's/\*core\.Base/*Base/g' internal/core/*.go
cat > internal/core/base.go <<'EOF'
package core

import (
	"github.com/brickKit/be-sdk-go/v3/evidence"
	"github.com/brickKit/be-sdk-go/v3/runtime"
)

// Base is what every module works with: the component's runtime (its database, events, audit, logger); the evidence
// writer of the changes that tighten access (nil: no evidence, the module run alone in tests); the deployment and
// implementation instance the source methods stamp their answers with (protocol 02); the time zone a new legal
// entity gets when none is given (DEFAULT_LEGAL_ENTITY_TIMEZONE).
type Base struct {
	RT          *runtime.Runtime
	Ev          *evidence.Writer
	Deployment  string
	Instance    string
	DefaultZone string
}
EOF
sed -i 's/m\.instance\b/m.Instance/g; s/m\.deployment\b/m.Deployment/g; s/m\.defaultZone\b/m.DefaultZone/g; s/m\.ev\b/m.Ev/g' internal/*/*.go
A="sdkauthz=github.com/brickKit/be-sdk-go/v3/authz $PV3"
for p in core entities units tightening replay source; do A="$A $p=$MOD/internal/$p"; done
python3 $S/aliases.py $A -- org/*.go internal/*/*.go
$G -w org/*.go internal/*/*.go
go build ./internal/...
echo INTERNAL-OK
cp $S/org-module.go org/module.go; cp $S/org-services.go org/services.go
mkdir -p itest
for f in checks org evidence; do git mv -f org/${f}_integration_test.go itest/${f}_integration_test.go; sed -i "s/^package org$/package itest/" itest/${f}_integration_test.go; done
A="$A org=$MOD/org"
python3 $S/aliases.py $A assert=github.com/stretchr/testify/assert require=github.com/stretchr/testify/require -- itest/*.go org/*.go
$G -w itest/*.go org/*.go
go build ./...
go vet ./...
go vet -tags integration ./...
echo PIPELINE-OK
