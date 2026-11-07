#!/bin/bash
# The layout of infra/iam-casdoor (layout-plan.md L4), replayable from the branch point. Stops at the first failure.
set -euo pipefail
S=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/13ed8ff2-682c-408f-9944-2835262837bb/scratchpad
C=/home/zhijie/Desktop/github/be-assembly-standard/components/infra/iam-casdoor
M=$S/mvdecl/mvdecl; G=$S/gobin/goimports; R=$S/restructure/restructure
MOD=github.com/brickKit/infra-iam-casdoor/v3
PV3="authzv3=github.com/brickKit/contract-infra-authz/v3/gen/go/be/authz/v3 jwt=github.com/golang-jwt/jwt/v5 sdkauthz=github.com/brickKit/be-sdk-go/v3/authz assert=github.com/stretchr/testify/assert require=github.com/stretchr/testify/require"
cd $C
git reset -q --hard HEAD && git clean -qfd internal iam itest
sed -i 's/  version: 3.0.38/  version: 3.0.39/' component.yaml
sed -i 's/Version = "3.0.38"/Version = "3.0.39"/' iam/definition.go
grep -q 'Version = "3.0.39"' iam/definition.go
cd iam
$M definition.go core_names.go ID StreamEnded Sessions Account DefaultTokenTTL Definitions
$M module.go login.go CookieName signedIn returnTo login callback session answerToken logout jwks devToken
$M tokens.go login.go issue
mv tokens.go $S/iam-tokens.go.left
$M module.go casdoor.go productCallLimit
$M module.go sessions.go endSessionsBeforeRecovery
$M sessions.go module.go Services
$M accountops.go module.go routesForAccounts
$M replay.go module.go Replays
$M replay.go store.go usernameOf replayStatus replayLogout lockAccount
$M accountops.go store.go reasonFor
$M reconcile.go product.go cut
$M reconcile.go store.go compare consoleIntent baselinePassword statusEvidence nullable optional InFlight
python3 - <<'EOF2'
import pathlib, re
p = pathlib.Path("accountops.go"); s = p.read_text()
s = s.replace("func (s store) managed(", "func (s store) managedAccount(")
s = re.sub(r"\.managed\(", ".managedAccount(", s)
p.write_text(s)
EOF2
$M accountops.go store.go managed managedAccount fence setStatus resetFactors
python3 - <<'EOF2'
import pathlib
p = pathlib.Path("sessions.go"); s = p.read_text()
old = "type sessions struct {"
assert s.count(old) == 1
s = s.replace(old, "// newSessions is the session service over the module.\nfunc newSessions(m *Module) *sessions { return &sessions{m: m} }\n\n" + old)
p.write_text(s)
p = pathlib.Path("module.go"); s = p.read_text()
assert s.count("&sessions{m: m}") == 1
p.write_text(s.replace("&sessions{m: m}", "newSessions(m)"))
EOF2
python3 $S/aliases.py $PV3 -- *.go
$G -w *.go
gofmt -w *.go
go build ./
go vet ./ >/dev/null
$R -dir . -map "core_names.go:core,store.go:core,evidence.go:core,keys.go:keys,casdoor.go:provider,product.go:provider,login.go:login,sessions.go:sessions,accounts.go:accounts,accountops.go:accounts,accountops_test.go:accounts,reconcile.go:reconcile,replay.go:replay,definition.go:,module.go:,manifest_test.go:,tokens_test.go:login,recovery_integration_test.go:itest,replay_integration_test.go:itest,compare_integration_test.go:itest,e2e_integration_test.go:itest,accountops_integration_test.go:itest,phases_integration_test.go:itest" -rename account=accountRow,target=targetOf -tests -tags integration -entry iam -apply > $S/iam-restructure.txt
echo REWRITE-OK
cd $C
mv_() { mkdir -p internal/$2; git mv -f iam/$1 internal/$2/$3 2>/dev/null || mv iam/$1 internal/$2/$3; sed -i "s/^package iam$/package $2/" internal/$2/$3; }
mv_ core_names.go core names.go; mv_ store.go core store.go; mv_ evidence.go core evidence.go
mv_ keys.go keys keys.go; mv_ casdoor.go provider casdoor.go; mv_ product.go provider product.go
mv_ login.go login login.go; mv_ tokens_test.go login tokens_test.go; mv_ sessions.go sessions sessions.go
mv_ accounts.go accounts accounts.go; mv_ accountops.go accounts accountops.go; mv_ accountops_test.go accounts accountops_test.go
mv_ reconcile.go reconcile reconcile.go; mv_ replay.go replay replay.go
sed -i 's/\*core\.Base/*Base/g' internal/core/*.go
python3 - <<'EOF2'
import pathlib, re
p = pathlib.Path('internal/core/store.go'); s = p.read_text()
s = s.replace('type Managed struct {\n\tAccount\n', 'type Managed struct {\n\tAccountRow\n')
s = re.sub(r'Managed\{(?:account|Account): ', 'Managed{AccountRow: ', s)
p.write_text(s)
EOF2
sed -i 's/^\tm \*Module$/\tm *core.Base/; s/^func NewSessions(m \*Module) \*sessions/func NewSessions(m *core.Base) *sessions/' internal/sessions/sessions.go
cat > internal/core/base.go <<'EOF'
package core

import (
	"time"

	"github.com/brickKit/be-sdk-go/v3/runtime"
	authzv3 "github.com/brickKit/contract-infra-authz/v3/gen/go/be/authz/v3"
	keys "github.com/brickKit/infra-iam-casdoor/v3/internal/keys"
	provider "github.com/brickKit/infra-iam-casdoor/v3/internal/provider"
)

// Base is what every module works with: the component's runtime; the store of sessions and accounts; the Casdoor
// clients and the signing keys; the tokens' issuer, audience and lifetimes; the session cookie's settings; the
// development exchange; the pull interval and the tightening window; the authorization member's account service.
type Base struct {
	RT       *runtime.Runtime
	Store    Store
	Impl     string // IMPLEMENTATION_INSTANCE: the ended stream's cursors name it
	Casdoor  *provider.Casdoor
	Keys     *keys.KeyRing
	Issuer   string
	Audience string
	TTL      time.Duration
	Idle     time.Duration
	Absolute time.Duration
	Secure   bool
	After    string
	Dev      bool
	PullEach time.Duration // P_pull
	Tight    time.Duration // T_tight
	Authz    authzv3.AccountServiceClient
}
EOF
python3 - <<'EOF'
import pathlib, re
fields = {"store": "Store", "impl": "Impl", "casdoor": "Casdoor", "keys": "Keys", "issuer": "Issuer", "audience": "Audience",
          "ttl": "TTL", "idle": "Idle", "absolute": "Absolute", "secure": "Secure", "after": "After", "dev": "Dev",
          "pullEach": "PullEach", "tight": "Tight", "authz": "Authz"}
for p in pathlib.Path("internal").glob("*/*.go"):
    s = p.read_text()
    s2 = re.sub(r"\bm\.(" + "|".join(fields) + r")\b", lambda m: "m." + fields[m.group(1)], s)
    if s2 != s:
        p.write_text(s2)
EOF
A="$PV3"
for p in core keys provider login sessions accounts reconcile replay; do A="$A $p=$MOD/internal/$p"; done
python3 $S/aliases.py $A -- iam/*.go internal/*/*.go
$G -w iam/*.go internal/*/*.go
python3 - <<'EOF2'
import pathlib
p = pathlib.Path("internal/login/tokens_test.go"); s = p.read_text()
for a, b in [("*Module", "*core.Base"), ("&Module{issuer: ", "&core.Base{Issuer: "), ("audience: ", "Audience: "),
             ("ttl: core.DefaultTokenTTL, keys: ", "TTL: core.DefaultTokenTTL, Keys: "), ("&Module{after: ", "&core.Base{After: ")]:
    assert a in s, a
    s = s.replace(a, b)
p.write_text(s)
EOF2
go build ./internal/...
echo INTERNAL-OK
cp $S/iam-module.go iam/module.go
sed -i 's/^\t\t\t\tref.Set(m.reconcile)$/\t\t\t\tref.Set(func(ctx context.Context) error { return reconcile.Reconcile(m.b, ctx) })/' iam/definition.go
mkdir -p itest
for f in recovery replay compare e2e accountops phases; do git mv -f iam/${f}_integration_test.go itest/${f}_integration_test.go; sed -i "s/^package iam$/package itest/" itest/${f}_integration_test.go; done
A="$A iam=$MOD/iam"
sed -i 's/\blogin\.CookieName\b/iamlogin.CookieName/g' itest/*.go
A="$A iamlogin=$MOD/internal/login"
python3 $S/aliases.py $A -- itest/*.go iam/*.go
$G -w itest/*.go iam/*.go
go build ./...
go vet ./...
go vet -tags integration ./...
echo PIPELINE-OK
