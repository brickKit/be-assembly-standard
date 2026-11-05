// Command drilltool is the T11 drill's changes to the identity and authorization members (item 4's gate, a full
// recovery's drill scenarios): prepare, before T, lets test.mdm.admin see, disable and reset the second factors of
// accounts (a grant by the authorization admin test.alice); after, after T, revokes test.mdm.viewer's grant, disables
// test.revoked, retires a unit and resets test.mdm.viewer's second factors; intent-only disables test.expired with its
// account row locked, so that its intent reaches the evidence store, then pauses the audit container (the evidence
// store alone) and lets the transaction commit: its conclusion stays in the identity member's evidence outbox;
// alert-only, with the store paused, disables test.rates: its intent goes to the alert channel. It prints what it did
// as JSON.
//
// Usage: drilltool prepare|after|intent-only|alert-only
// env: IAM_URL, AUTHZ_URL, ORG_URL, BE_ACC_IAM_TEST_PASSWORD; after: GRANT, UNIT; intent-only: PG_DSN (the cell's
// database), AUDIT_CONTAINER
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
	"github.com/brickKit/be-sdk-go/v3/seed"
	"github.com/jackc/pgx/v5"
)

const (
	account   = "infra.iam.account"
	opView    = "infra.iam.account.read"
	opDisable = "infra.iam.account.disable"
	opReset   = "infra.iam.account.reset_second_factor"
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
	return "t11:" + hex.EncodeToString(b)
}

func main() {
	if len(os.Args) != 2 {
		must(fmt.Errorf("usage: drilltool prepare|after|intent-only|alert-only"))
	}
	iam, authzURL, org := os.Getenv("IAM_URL"), os.Getenv("AUTHZ_URL"), os.Getenv("ORG_URL")
	accounts, err := seed.Accounts(iam, os.Getenv("BE_ACC_IAM_TEST_PASSWORD"), "test.alice", "test.mdm.admin",
		"test.mdm.viewer", "test.revoked", "test.expired", "test.rates")
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
			seed.Segment(account, opDisable, "account"), seed.Segment(account, opReset, "account")})
		must(err)
		out["grant"] = g
		must(asAdmin.WaitGranted("GET", "/api/iam/accounts/"+accounts["test.rates"].Principal, 90*time.Second))
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
	case "alert-only":
		start := time.Now()
		must(disable(asAdmin, "test.rates"))
		out["disabled"] = accounts["test.rates"].Principal
		out["took_ms"] = time.Since(start).Milliseconds() // the intent's wait for the store, then the alert channel
	default:
		must(fmt.Errorf("usage: drilltool prepare|after|intent-only|alert-only"))
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
