// Command tighten is the T9e drill's tightenings (item 4, a full recovery's step 6): prepare, before T, lets
// test.mdm.admin see and disable accounts (a grant by the authorization admin test.alice: an account not visible
// answers 404 whatever the operation, so the view operation comes with it); after, after T, makes three
// tightenings the recovery puts back by their evidence: test.alice revokes test.mdm.viewer's grant, test.mdm.admin
// disables test.revoked and retires a unit. It prints what it did as JSON (the drill checks it after the replay).
//
// Usage: tighten prepare|after   (env: IAM_URL, AUTHZ_URL, ORG_URL, BE_ACC_IAM_TEST_PASSWORD; after: GRANT, UNIT)
package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"time"

	sdkauthz "github.com/brickKit/be-sdk-go/v3/authz"
	"github.com/brickKit/be-sdk-go/v3/seed"
)

const (
	account   = "infra.iam.account"
	opView    = "infra.iam.account.read"
	opDisable = "infra.iam.account.disable"
)

func must(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "tighten:", err)
		os.Exit(1)
	}
}

func key() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return "t9e:" + hex.EncodeToString(b)
}

func main() {
	if len(os.Args) != 2 {
		must(fmt.Errorf("usage: tighten prepare|after"))
	}
	iam, authzURL, org := os.Getenv("IAM_URL"), os.Getenv("AUTHZ_URL"), os.Getenv("ORG_URL")
	accounts, err := seed.Accounts(iam, os.Getenv("BE_ACC_IAM_TEST_PASSWORD"), "test.alice", "test.mdm.admin",
		"test.mdm.viewer", "test.revoked")
	must(err)
	alice, admin, revoked := accounts["test.alice"], accounts["test.mdm.admin"], accounts["test.revoked"]
	a, err := seed.NewAuthz(authzURL, alice.Token, "drill/t9e")
	must(err)
	out := map[string]any{}
	switch os.Args[1] {
	case "prepare":
		view := seed.Segment(account, opView, "account")
		view.ReadFields = []string{"principal", "status"}
		g, err := a.Grant("manage-accounts", "", admin.Principal, []sdkauthz.Segment{view, seed.Segment(account, opDisable, "account")})
		must(err)
		out["grant"] = g
		// granted once test.mdm.admin sees test.revoked's account (the grant reaches the identity member's view)
		c := seed.NewClient(iam, admin.Token)
		deadline := time.Now().Add(90 * time.Second)
		for {
			code, _, err := c.Do("GET", "/api/iam/accounts/"+revoked.Principal, nil)
			must(err)
			if code == 200 {
				break
			}
			if time.Now().After(deadline) {
				must(fmt.Errorf("test.mdm.admin does not see the account within 90 s (last %d)", code))
			}
			time.Sleep(time.Second)
		}
	case "after":
		r, err := a.Revoke("revoke-viewer", os.Getenv("GRANT"))
		must(err)
		out["revoked"] = map[string]any{"grant": os.Getenv("GRANT"), "record": r}
		_, err = seed.NewClient(iam, admin.Token).Must("POST", "/api/iam/accounts/"+revoked.Principal+"/disable",
			map[string]any{}, "Idempotency-Key", key())
		must(err)
		out["disabled"] = revoked.Principal
		_, err = seed.NewClient(org, admin.Token).Must("POST", "/api/org/units/"+os.Getenv("UNIT")+"/retire",
			map[string]any{}, "Idempotency-Key", key())
		must(err)
		out["retired"] = os.Getenv("UNIT")
	default:
		must(fmt.Errorf("usage: tighten prepare|after"))
	}
	b, _ := json.Marshal(out)
	fmt.Println(string(b))
}
