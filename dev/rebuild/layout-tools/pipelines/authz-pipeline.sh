#!/bin/bash
# The layout of infra/authz (layout-plan.md L4), replayable from the branch point. Stops at the first failure.
set -euo pipefail
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad
C=/home/zhijie/Desktop/github/be-assembly-standard/components/infra/authz
M=$S/mvdecl/mvdecl; G=$S/gobin/goimports; R=$S/restructure/restructure
MOD=github.com/brickKit/infra-authz/v3
PV3="authzv3=github.com/brickKit/contract-infra-authz/v3/gen/go/be/authz/v3 sdkauthz=github.com/brickKit/be-sdk-go/v3/authz assert=github.com/stretchr/testify/assert require=github.com/stretchr/testify/require pgx=github.com/jackc/pgx/v5"
cd $C
git reset -q --hard HEAD && git clean -qfd authz internal itest
sed -i 's/  version: 3.0.41/  version: 3.0.42/' component.yaml
sed -i 's/Version = "3.0.41"/Version = "3.0.42"/' authz/definition.go
grep -q 'Version = "3.0.42"' authz/definition.go
cd authz
python3 - <<'EOF2'
import pathlib, re
# the registry's cache method would collide with its type once both are package-level
for f in pathlib.Path(".").glob("*.go"):
    s = f.read_text()
    s2 = s.replace("func (m *Module) registry() (registry, error)", "func (m *Module) registryNow() (registry, error)")
    s2 = re.sub(r"\bm\.registry\(\)", "m.registryNow()", s2)
    if s2 != s:
        f.write_text(s2)
EOF2
python3 - <<'EOF2'
import pathlib
# a record's state moved: the plans follow it (planrun.go) through a hook the entry sets, not a call from the effect point
p = pathlib.Path("enact.go"); s = p.read_text()
a = "return rev, m.followRecord(ctx, tx, id, state) // a plan item waiting on it (planrun.go)"
assert s.count(a) == 1
p.write_text(s.replace(a, "return rev, m.recordMoved(ctx, tx, id, state) // a plan item waiting on it (the plans module)"))
p = pathlib.Path("module.go"); s = p.read_text()
a = "\tplanConfirmAbove        int // AUTHZ_PLAN_MAX_AGE, AUTHZ_PLAN_CONFIRM_ABOVE (A132)\n"
assert s.count(a) == 1
s = s.replace(a, a + "\t// recordMoved is told when the effect point moves a record's state, in its transaction: the plans follow it\n\trecordMoved func(ctx context.Context, tx db.Tx, record, state string) error\n")
a = "\treturn m, nil\n}"
assert s.count(a) == 1
p.write_text(s.replace(a, "\tm.recordMoved = m.followRecord\n" + a))
EOF2
$M plan.go facts.go standingOf
$M confirm.go confirmroutes.go confirmHTTP ownerPayloadHTTP
$M definition.go core_names.go ID Records AccountStream Accounts DefaultSourceHigh Definitions
$M submit.go core_registry.go registry parseRegistry owner usable
$M module.go core_registry.go registryNow
$M view.go core_state.go state readState
$M submit.go core_state.go advance
$M target.go core_state.go uuidText
$M replay.go decide.go replayFacts
$M scheduled.go module.go Jobs
$M replay.go module.go Replays
$M module.go routes.go changeHTTP tightenHTTP relinquishHTTP holderFacts answer changeByKey recordsHTTP
$M security_test.go submit_test.go TestCrossCheck TestSubmissionRules
$M security_test.go view_test.go TestShardKeysAreKeys
$M security_test.go manifest_test.go TestTheModuleIsMergeSafe
python3 $S/aliases.py $PV3 -- *.go
$G -w *.go
gofmt -w *.go
go build ./
go vet ./ >/dev/null
go vet -tags integration ./ >/dev/null
echo PRESPLIT-OK
$R -dir . -map "$(cat $S/authz-map.txt)" -tests -tags integration -entry authz -apply > $S/authz-restructure.txt
echo REWRITE-OK
cd $C
mv_() { mkdir -p internal/$2; git mv -f authz/$1 internal/$2/$3 2>/dev/null || mv authz/$1 internal/$2/$3; sed -i "s/^package authz$/package $2/" internal/$2/$3; }
mv_ core_names.go core names.go; mv_ core_registry.go core registry.go; mv_ core_state.go core state.go
for f in security effective decide security_test effective_test decide_test; do mv_ $f.go core $f.go; done
mv_ submit.go definitions submit.go; mv_ submit_test.go definitions submit_test.go
for f in change facts requester target enact effect scheduled cooling confirm delegate budget disposition signal release pending closure routes budget_test delegate_test disposition_test requester_test; do mv_ $f.go effectpoint $f.go; done
mv_ claim.go claim claim.go; mv_ claim_test.go claim claim_test.go
mv_ accountchange.go accounts accountchange.go
mv_ view.go view view.go; mv_ view_test.go view view_test.go
mv_ replay.go restore replay.go; mv_ recoverystep.go restore recoverystep.go
for f in plan planrun planhttp plan_test; do mv_ $f.go plans $f.go; done
mv_ recovery.go adminrecovery recovery.go
mv_ confirmroutes.go confirmroutes confirmroutes.go
sed -i 's/\*core\.Base/*Base/g' internal/core/*.go
cat > internal/core/base.go <<'EOF2'
package core

import (
	"context"
	"sync"
	"time"

	"github.com/brickKit/be-sdk-go/v3/db"
	"github.com/brickKit/be-sdk-go/v3/projection"
	"github.com/brickKit/be-sdk-go/v3/runtime"
)

// Base is what every module works with: the component's runtime; the deployment and this member's instance; the
// registry (AUTHZ_REGISTRY, parsed again only when it changes: RegistryNow); the identity member's account status with
// its watermark and the source's bounds (D_src_high, D_src_read, T_tight, security 03); the unit depth (A131); the
// plans' bounds (A132); and the hook the effect point calls when it moves a record's state.
type Base struct {
	RT                   *runtime.Runtime
	Deployment, Instance string
	RegistryText         func() string

	mu      sync.Mutex
	regText string
	reg     Registry

	Accounts                *projection.Watermarked
	SrcHigh, SrcRead, Tight time.Duration
	MaxDepth                int           // AUTHZ_MAX_UNIT_DEPTH (A131)
	PlanMaxAge              time.Duration // AUTHZ_PLAN_MAX_AGE (A132)
	PlanConfirmAbove        int           // AUTHZ_PLAN_CONFIRM_ABOVE (A132)
	// RecordMoved is told when the effect point moves a record's state, in its transaction: the plans follow it
	// (the entry sets it to the plans module's FollowRecord)
	RecordMoved func(ctx context.Context, tx db.Tx, record, state string) error
}
EOF2
python3 - <<'EOF2'
import pathlib, re
fields = {"deployment": "Deployment", "instance": "Instance", "registryText": "RegistryText", "accounts": "Accounts",
          "srcHigh": "SrcHigh", "srcRead": "SrcRead", "tight": "Tight", "maxDepth": "MaxDepth", "planMaxAge": "PlanMaxAge",
          "planConfirmAbove": "PlanConfirmAbove", "recordMoved": "RecordMoved"}
for p in pathlib.Path("internal").glob("*/*.go"):
    s = p.read_text()
    s2 = re.sub(r"\bm\.(" + "|".join(fields) + r")\b", lambda m: "m." + fields[m.group(1)], s)
    if s2 != s:
        p.write_text(s2)
p = pathlib.Path("internal/confirmroutes/confirmroutes.go"); s = p.read_text()
for a, b in [("m.confirmDisposition", "effectpoint.ConfirmDisposition"), ("m.confirmPlan", "plans.ConfirmPlan"),
             ("m.confirmAccount", "accounts.ConfirmAccount"), ("confirm(ctx, tx, u.Subject, in)", "confirm(m, ctx, tx, u.Subject, in)")]:
    assert a in s, a
    s = s.replace(a, b)
p.write_text(s)
EOF2
A="$PV3"
for p in core definitions effectpoint claim accounts view restore plans adminrecovery confirmroutes; do A="$A $p=$MOD/internal/$p"; done
python3 $S/aliases.py $A -- authz/*.go internal/*/*.go
$G -w authz/*.go internal/*/*.go
go build ./internal/...
echo INTERNAL-OK
# unit tests: a test helper stays in its package (SF22): core's own helpers are unexported again, and the two packages
# whose tests used them have their own copies; the registry's view test goes with the view
python3 - <<'EOF2'
import pathlib, re
for p in pathlib.Path("internal/core").glob("*_test.go"):
    s = p.read_text()
    s2 = re.sub(r"\bVals\b", "vals", s); s2 = re.sub(r"\bOseg\b", "oseg", s2); s2 = re.sub(r"\bJan\b", "jan", s2)
    if s2 != s:
        p.write_text(s2)
p = pathlib.Path("internal/effectpoint/budget_test.go"); s = p.read_text()
s = s.replace("core.Vals", "vals").replace("core.Oseg", "oseg").replace("core.Jan", "jan")
p.write_text(s)
helpers = '''
// vals, oseg and jan are core's test helpers (internal/core/effective_test.go): a value set, one order segment, a date.
func vals(v ...string) sdkauthz.Atom { return sdkauthz.Atom{Kind: "in", Values: v} }

func oseg(op string, atom sdkauthz.Atom, fields []string, from, until string) sdkauthz.Segment {
	return sdkauthz.Segment{ResourceType: "demo.order", Operation: op, Atoms: map[string]sdkauthz.Atom{"region": atom},
		ReadFields: fields, Valid: sdkauthz.Window{From: from, Until: until}}
}

const jan = "2026-01-01T00:00:00Z"
'''
pathlib.Path("internal/effectpoint/helpers_test.go").write_text("package effectpoint\n" + helpers)
pathlib.Path("internal/view/helpers_test.go").write_text("package view\n" + helpers +
    '\nfunc all() sdkauthz.Atom { return sdkauthz.Atom{Kind: "all"} }\n')
p = pathlib.Path("internal/definitions/submit_test.go"); s = p.read_text()
assert s.count("m := &Module{}") == 1
p.write_text(s.replace("m := &Module{}", "m := &core.Base{}"))
EOF2
$M internal/core/effective_test.go internal/view/view_test.go TestOnlyUsableKeysTakePart
python3 - <<'EOF2'
import pathlib, re
p = pathlib.Path("internal/view/view_test.go"); s = p.read_text()
s = s.replace("view.Defined", "Defined"); s = re.sub(r"(?<![\w.])ParseRegistry\(", "core.ParseRegistry(", s)
p.write_text(s)
EOF2
python3 $S/aliases.py $A -- internal/*/*.go
$G -w internal/*/*.go
go vet ./internal/...
echo UNIT-OK
cp $S/authz-module.go authz/module.go
cp $S/authz-services.go authz/services.go
go build ./authz/
mkdir -p itest
for f in authz/*_integration_test.go; do b=$(basename $f); git mv -f $f itest/$b; sed -i "s/^package authz$/package itest/" itest/$b; done
A="$A authz=$MOD/authz"
python3 $S/aliases.py $A -- itest/*.go authz/*.go
sed -i 's/\bauthz\.RecoveryRequest\b/adminrecovery.RecoveryRequest/g' cmd/recover/*.go
python3 $S/aliases.py $A -- cmd/recover/*.go
$G -w cmd/recover/*.go
$G -w itest/*.go authz/*.go
go build ./...
go vet ./...
go vet -tags integration ./...
echo PIPELINE-OK
# merge safety covers the business modules too: the entry package and every package under internal/
python3 - <<'EOF2'
import pathlib
p = pathlib.Path("authz/manifest_test.go"); s = p.read_text()
a = '''// TestTheModuleIsMergeSafe: the module is compiled into the Go infra shell.
func TestTheModuleIsMergeSafe(t *testing.T) {
	findings, err := mergesafety.CheckDir(".")
	require.NoError(t, err)
'''
b = '''// TestTheModuleIsMergeSafe: the module is compiled into the Go infra shell: the entry package and every business
// module under internal/.
func TestTheModuleIsMergeSafe(t *testing.T) {
	findings, err := mergesafety.CheckDir(".")
	require.NoError(t, err)
	inner, err := mergesafety.CheckTree("../internal")
	require.NoError(t, err)
	findings = append(findings, inner...)
'''
assert s.count(a) == 1
p.write_text(s.replace(a, b))
p = pathlib.Path("Makefile")
p.write_text('''.PHONY: test test-integration lint seed

test:  ## unit tests: the decision table, the containment and intersection rules, the registry, submissions, the manifest, merge safety
	go vet ./... && go test ./...

test-integration:  ## L2 against PostgreSQL (AUTHZ_IT_PG_PASSWORD) and be-sdk-go's sectest deployment; see itest/AGENTS.md
	go test -count=1 -tags integration ./itest/

lint:
	brickkit lint

seed:  ## the seed data for people: grants of this member's own operations (SEED_PASSWORD; see cmd/seed)
	-$(MAKE) -C ../iam-casdoor seed   # the identity member's seed accounts first; skipped when Casdoor is not reachable
	go run ./cmd/seed
''')
EOF2
go test ./authz/
echo FINAL-OK
python3 $S/doccap.py internal/*/*.go authz/*.go itest/*.go
sed -i 's#^// Run: go test -tags integration ./member/#// Run: go test -tags integration ./itest/ (make test-integration)#' itest/authz_integration_test.go
gofmt -l internal authz itest cmd
echo DOCCAP-OK
