// Command drilltool is the T13e drill's changes (T11's, and freeze-release, double-failure, forge) to the identity and authorization members (item 4's gate, a full
// recovery's drill scenarios): prepare, before T, lets test.mdm.admin see, disable and reset the second factors of
// accounts (a grant by the authorization admin test.alice); after, after T, revokes test.mdm.viewer's grant, disables
// test.revoked, retires a unit and resets test.mdm.viewer's second factors; intent-only disables test.expired with its
// account row locked, so that its intent reaches the evidence store, then pauses the audit container (the evidence
// store alone) and lets the transaction commit: its conclusion stays in the identity member's evidence outbox;
// alert-only, with the store paused, disables test.rates: its intent goes to the alert channel. It prints what it did
// as JSON. T13e adds: freeze-release freezes test.sales.multi (the authorization member derives an identity-side
// disposition) and test.alice releases the disposition; double-failure pauses the evidence store and the object store
// (the alert channel) while test.sales.es is disabled, so neither takes its intent, and waits for the double failure's
// own record in the evidence store; forge writes three alert-channel records no recovery may execute (P12.4, P12.26):
// one signed by a revoked credential, one by a credential under a revoked CA, one by another component's valid
// credential naming the identity member as its writer; enable, after the recovery, enables test.sales.multi and
// test.sales.es again (the scenarios sign them in).
//
// Usage: drilltool prepare|after|intent-only|alert-only|freeze-release|double-failure|forge|enable
// env: IAM_URL, AUTHZ_URL, ORG_URL, BE_ACC_IAM_TEST_PASSWORD; after: GRANT, UNIT; intent-only, freeze-release,
// double-failure: PG_DSN (the cell's database), AUDIT_CONTAINER; double-failure: S3_CONTAINER; forge: DEPLOYMENT_ID,
// RUN_PROFILE_*, TLS_CA (the trust root), LEAKED, OLD, SALES (credential file bases: <base>.cert.pem, .key.pem),
// FORGE_ADMIN, FORGE_OTHER (the principals the forged intents name)
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"time"

	sdkauthz "github.com/brickKit/be-sdk-go/v3/authz"
	"github.com/brickKit/be-sdk-go/v3/identity"
	"github.com/brickKit/be-sdk-go/v3/ids"
	"github.com/brickKit/be-sdk-go/v3/runprofile"
	"github.com/brickKit/be-sdk-go/v3/seed"
	"github.com/jackc/pgx/v5"
)

const (
	account   = "infra.iam.account"
	opView    = "infra.iam.account.read"
	opDisable = "infra.iam.account.disable"
	opReset   = "infra.iam.account.reset_second_factor"
	opFreeze  = "infra.iam.account.freeze"
	opEnable  = "infra.iam.account.enable"
)

func must(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "drilltool:", err)
		os.Exit(1)
	}
}

func key() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return "t13e:" + hex.EncodeToString(b)
}

func main() {
	if len(os.Args) != 2 {
		must(fmt.Errorf("usage: drilltool prepare|after|intent-only|alert-only"))
	}
	iam, authzURL, org := os.Getenv("IAM_URL"), os.Getenv("AUTHZ_URL"), os.Getenv("ORG_URL")
	// each command signs in only the accounts it uses: one disabled earlier in the drill cannot sign in any more
	users := map[string][]string{"prepare": {"test.alice", "test.mdm.admin", "test.mdm.viewer", "test.revoked",
		"test.expired", "test.rates"}, "after": {"test.alice", "test.mdm.admin", "test.mdm.viewer", "test.revoked"},
		"intent-only": {"test.mdm.admin", "test.expired"}, "alert-only": {"test.mdm.admin", "test.rates"},
		"freeze-release": {"test.alice", "test.mdm.admin"},
		"double-failure": {"test.mdm.admin", "test.sales.es"}, "forge": {}, "enable": {"test.mdm.admin"}}[os.Args[1]]
	if users == nil {
		must(fmt.Errorf("usage: drilltool prepare|after|intent-only|alert-only|freeze-release|double-failure|forge|enable"))
	}
	if os.Args[1] == "forge" {
		b, _ := json.Marshal(forge())
		fmt.Println(string(b))
		return
	}
	accounts, err := seed.Accounts(iam, os.Getenv("BE_ACC_IAM_TEST_PASSWORD"), users...)
	must(err)
	alice, admin := accounts["test.alice"], accounts["test.mdm.admin"]
	asAdmin := seed.NewClient(iam, admin.Token)
	disable := func(c seed.Client, who string) error {
		_, err := c.Must("POST", "/api/iam/accounts/"+accounts[who].Principal+"/disable", map[string]any{}, "Idempotency-Key", key())
		return err
	}
	out := map[string]any{}
	switch os.Args[1] {
	case "prepare":
		a, err := seed.NewAuthz(authzURL, alice.Token, "drill/t11")
		must(err)
		view := seed.Segment(account, opView, "account")
		view.ReadFields = []string{"principal", "status"}
		g, err := a.Grant("manage-accounts", "", admin.Principal, []sdkauthz.Segment{view,
			seed.Segment(account, opDisable, "account"), seed.Segment(account, opReset, "account"),
			seed.Segment(account, opFreeze, "account"), seed.Segment(account, opEnable, "account")})
		must(err)
		out["grant"] = g
		// granted once test.mdm.admin sees the accounts (one grant record: its segments reach the view together)
		deadline := time.Now().Add(90 * time.Second)
		for {
			code, _, err := asAdmin.Do("GET", "/api/iam/accounts/"+accounts["test.rates"].Principal, nil)
			must(err)
			if code == 200 {
				break
			}
			if time.Now().After(deadline) {
				must(fmt.Errorf("test.mdm.admin does not see the account within 90 s (last %d)", code))
			}
			time.Sleep(time.Second)
		}
		out["accounts"] = map[string]string{"test.mdm.viewer": accounts["test.mdm.viewer"].Principal,
			"test.revoked": accounts["test.revoked"].Principal, "test.expired": accounts["test.expired"].Principal,
			"test.rates": accounts["test.rates"].Principal}
	case "after":
		a, err := seed.NewAuthz(authzURL, alice.Token, "drill/t11")
		must(err)
		r, err := a.Revoke("revoke-viewer", os.Getenv("GRANT"))
		must(err)
		out["revoked"] = map[string]any{"grant": os.Getenv("GRANT"), "record": r}
		must(disable(asAdmin, "test.revoked"))
		out["disabled"] = accounts["test.revoked"].Principal
		_, err = seed.NewClient(org, admin.Token).Must("POST", "/api/org/units/"+os.Getenv("UNIT")+"/retire",
			map[string]any{}, "Idempotency-Key", key())
		must(err)
		out["retired"] = os.Getenv("UNIT")
		_, err = asAdmin.Must("POST", "/api/iam/accounts/"+accounts["test.mdm.viewer"].Principal+"/reset-second-factor",
			map[string]any{}, "Idempotency-Key", key())
		must(err)
		out["factors_reset"] = accounts["test.mdm.viewer"].Principal
	case "intent-only":
		out = intentOnly(asAdmin, accounts["test.expired"].Principal, disable)
	case "freeze-release":
		out = freezeRelease(asAdmin, seed.NewClient(authzURL, alice.Token), principalOf("test.sales.multi"))
	case "double-failure":
		out = doubleFailure(asAdmin, accounts["test.sales.es"].Principal)
	case "enable": // after the recovery: the frozen account back for the scenarios that sign it in
		for _, who := range []string{"test.sales.multi", "test.sales.es"} { // scenarios 9 and 10 left them frozen, disabled
			out[who] = ask(asAdmin, "/api/iam/accounts/"+principalOf(who)+"/enable")
		}
	case "alert-only":
		start := time.Now()
		must(disable(asAdmin, "test.rates"))
		out["disabled"] = accounts["test.rates"].Principal
		out["took_ms"] = time.Since(start).Milliseconds() // the intent's wait for the store, then the alert channel
	default:
		must(fmt.Errorf("usage: drilltool prepare|after|intent-only|alert-only|freeze-release|double-failure|forge|enable"))
	}
	b, _ := json.Marshal(out)
	fmt.Println(string(b))
}

// intentOnly: the account's row locked (the identity member's lock wait is 2 s, so all of this fits in it), the
// disablement asked; once its intent is in the evidence store, the audit container paused, the lock let go.
func intentOnly(asAdmin seed.Client, principal string, disable func(seed.Client, string) error) map[string]any {
	ctx := context.Background()
	conn, err := pgx.Connect(ctx, os.Getenv("PG_DSN"))
	must(err)
	defer conn.Close(ctx)
	tx, err := conn.Begin(ctx)
	must(err)
	_, err = tx.Exec(ctx, "SELECT 1 FROM infra_iam_casdoor.iam_account WHERE principal = $1 FOR UPDATE", principal)
	must(err)
	start := time.Now()
	done := make(chan error, 1)
	go func() { done <- disable(asAdmin, "test.expired") }()
	intent := func() bool {
		var n int
		must(conn.QueryRow(ctx, `SELECT count(*) FROM infra_audit.audit_evidence WHERE category = 'account_status'
			AND phase = 'intent' AND convert_from(record, 'UTF8')::jsonb->'object'->>'id' = $1 AND received_at > $2`,
			principal, start.Add(-time.Second)).Scan(&n))
		return n > 0
	}
	for !intent() {
		if time.Since(start) > 10*time.Second {
			must(fmt.Errorf("the disablement's intent did not reach the evidence store within 10 s"))
		}
		time.Sleep(10 * time.Millisecond)
	}
	seen := time.Since(start)
	must(exec.Command("docker", "pause", os.Getenv("AUDIT_CONTAINER")).Run())
	paused := time.Since(start)
	must(tx.Rollback(ctx)) // the lock let go: the identity member's transaction commits
	must(<-done)
	var concluded int
	must(conn.QueryRow(ctx, `SELECT count(*) FROM infra_audit.audit_evidence WHERE category = 'account_status'
		AND phase <> 'intent' AND convert_from(record, 'UTF8')::jsonb->'object'->>'id' = $1 AND received_at > $2`,
		principal, start.Add(-time.Second)).Scan(&concluded))
	if concluded != 0 {
		must(fmt.Errorf("the conclusion reached the evidence store before it was paused"))
	}
	return map[string]any{"disabled": principal, "intent_seen_ms": seen.Milliseconds(), "paused_ms": paused.Milliseconds(),
		"answered_ms": time.Since(start).Milliseconds()}
}

// poll runs q (one integer) on the cell's database until it is not 0, at most limit.
func poll(conn *pgx.Conn, limit time.Duration, q string, args ...any) {
	start := time.Now()
	for {
		var n int
		must(conn.QueryRow(context.Background(), q, args...).Scan(&n))
		if n != 0 {
			return
		}
		if time.Since(start) > limit {
			must(fmt.Errorf("not within %s: %s %v", limit, q, args))
		}
		time.Sleep(200 * time.Millisecond)
	}
}

// freezeRelease: the account frozen (an identity-side disposition derived by the authorization member, CP73), then
// the disposition released by the root's holder (test.alice); both after T, so a recovery replays the freeze, derives
// the disposition again under another identity, and finds the release by its signal refs (CP102, CP107, CP112).
func freezeRelease(asAdmin, asAlice seed.Client, principal string) map[string]any {
	conn, err := pgx.Connect(context.Background(), os.Getenv("PG_DSN"))
	must(err)
	defer conn.Close(context.Background())
	codes := ask(asAdmin, "/api/iam/accounts/"+principal+"/freeze")
	const active = `SELECT count(*) FROM infra_authz.authz_disposition WHERE subject = $1 AND origin = 'identity_side'
		AND state = 'active'`
	poll(conn, 60*time.Second, active, principal)
	var id string
	var revision int64
	var refs []string // an identity-side release names the signal records it removes (CP107) and binds the revision
	must(conn.QueryRow(context.Background(), `SELECT id, revision, signal_ref FROM infra_authz.authz_disposition
		WHERE subject = $1 AND origin = 'identity_side' AND state = 'active'`, principal).Scan(&id, &revision, &refs))
	code, body, err := asAlice.Do("POST", "/api/authz/dispositions/"+id+"/release", map[string]any{"change_key": key(),
		"signal_refs": refs, "disposition_revision": map[string]any{"domain": "authz.disposition.revision",
			"value": fmt.Sprint(revision)}}, "Idempotency-Key", key())
	must(err)
	if code != 200 {
		must(fmt.Errorf("the release answered %d: %s", code, body))
	}
	poll(conn, 30*time.Second, `SELECT count(*) FROM infra_authz.authz_disposition WHERE id = $1 AND state = 'released'`, id)
	return map[string]any{"frozen": principal, "answers": codes, "disposition": id, "signal_refs": refs, "released": true}
}

// doubleFailure: the evidence store and the object store (the run profile's alert channel) paused; the account
// disabled (the tightening is not put off for the evidence, P12.8); both back; the double failure's own record (P12.23)
// reaches the evidence store through the outbox.
func doubleFailure(asAdmin seed.Client, principal string) map[string]any {
	conn, err := pgx.Connect(context.Background(), os.Getenv("PG_DSN"))
	must(err)
	defer conn.Close(context.Background())
	audit, s3 := os.Getenv("AUDIT_CONTAINER"), os.Getenv("S3_CONTAINER")
	must(exec.Command("docker", "pause", audit).Run())
	must(exec.Command("docker", "pause", s3).Run())
	start := time.Now()
	codes := ask(asAdmin, "/api/iam/accounts/"+principal+"/disable")
	took := time.Since(start)
	must(exec.Command("docker", "unpause", s3).Run())
	must(exec.Command("docker", "unpause", audit).Run())
	poll(conn, 90*time.Second, `SELECT count(*) FROM infra_audit.audit_evidence WHERE category = 'evidence_double_failure'
		AND convert_from(record, 'UTF8')::jsonb->'object'->>'id' = $1`, principal)
	var intents int
	must(conn.QueryRow(context.Background(), `SELECT count(*) FROM infra_audit.audit_evidence WHERE category = 'account_status'
		AND phase = 'intent' AND convert_from(record, 'UTF8')::jsonb->'object'->>'id' = $1 AND received_at > $2`,
		principal, start.Add(-time.Second)).Scan(&intents))
	return map[string]any{"disabled": principal, "answers": codes, "took_ms": took.Milliseconds(), "intents_in_the_store": intents,
		"double_failure_in_the_store": true}
}

// forge writes three alert-channel records, each an account_status intent "recorded" by the identity member (an
// evidence record as the SDK writes it), that a recovery must not execute: signed by a revoked credential of the
// identity member (RC71), by its credential under the revoked CA (RC86), and by the sales component's valid
// credential with the identity member as the writer (P12.4). A subject that is an authorization admin is not closed
// in 6.5 (FORGE_ADMIN); the other one is (FORGE_OTHER).
func forge() map[string]any {
	ctx := context.Background()
	dep, ca := os.Getenv("DEPLOYMENT_ID"), os.Getenv("TLS_CA")
	out := map[string]any{}
	for _, f := range []struct{ name, base, component, subject string }{
		{"revoked-credential", os.Getenv("LEAKED"), "infra/iam-casdoor", os.Getenv("FORGE_ADMIN")},
		{"revoked-ca", os.Getenv("OLD"), "infra/iam-casdoor", os.Getenv("FORGE_OTHER")},
		{"writer-not-signer", os.Getenv("SALES"), "erp/sales", os.Getenv("FORGE_OTHER")},
	} {
		tls, err := identity.LoadServiceTLS(dep, f.component, f.base+".cert.pem", f.base+".key.pem", ca, os.ReadFile)
		must(err)
		st, err := runprofile.New(runprofile.Options{Endpoint: os.Getenv("RUN_PROFILE_URL"),
			Bucket: os.Getenv("RUN_PROFILE_BUCKET"), AccessKey: os.Getenv("RUN_PROFILE_ACCESS_KEY"),
			Secret: func() string { return os.Getenv("RUN_PROFILE_SECRET_KEY") }, Deployment: dep,
			Writer: runprofile.Writer{Component: "infra/iam-casdoor", Instance: "forged"}, Identity: tls})
		must(err)
		id := ids.New().String()
		rec := map[string]any{"record_type": "be.evidence.record", "schema": "1.0", "id": id,
			"recorder": map[string]string{"component": "infra/iam-casdoor", "instance": "forged"},
			"category": "account_status", "phase": "intent", "subject": f.subject,
			"object": map[string]string{"type": "infra.iam.account", "id": f.subject, "version": "9999"},
			"change": map[string]string{"status": "disabled"}, "at": time.Now().UTC().Format("2006-01-02T15:04:05.000000Z")}
		_, err = st.Append(ctx, runprofile.KindAlert, rec)
		must(err)
		out[f.name] = map[string]string{"id": id, "subject": f.subject}
	}
	return out
}

// ask posts an account operation until it answers 200, at most three times: a timeout (504) is an unknown outcome, and
// asking again is what a client does (the operation on an account already in its target state answers it as it is).
// T13e attempt 1: Casdoor took 5.5 s to forbid test.sales.multi, the identity member's deadline is 3 s. The answers
// are returned for the record.
func ask(c seed.Client, path string) []int {
	k := key()
	var codes []int
	for {
		code, body, err := c.Do("POST", path, map[string]any{}, "Idempotency-Key", k)
		must(err)
		codes = append(codes, code)
		if code == 200 {
			return codes
		}
		if code < 500 || len(codes) == 3 {
			must(fmt.Errorf("%s answered %v: %s", path, codes, body))
		}
		time.Sleep(3 * time.Second)
	}
}

// principalOf reads an account's principal from the identity member's table: a frozen account cannot sign in to say it.
func principalOf(username string) string {
	conn, err := pgx.Connect(context.Background(), os.Getenv("PG_DSN"))
	must(err)
	defer conn.Close(context.Background())
	var p string
	must(conn.QueryRow(context.Background(), `SELECT principal FROM infra_iam_casdoor.iam_account WHERE username = $1`,
		"brickkit/"+username).Scan(&p))
	return p
}
