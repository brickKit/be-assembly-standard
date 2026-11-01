// Step 12, V6 second part: one module with a member that requires be-sdk-go alpha.23 (test/probe-go 3.2.21) and one
// that requires alpha.37 (erp/sales 3.0.16), as a Go shell would compile them. Which SDK does the binary hold?
package main

import (
	_ "github.com/brickKit/be-acceptance/probes/go/v3/probe"
	_ "github.com/brickKit/erp-sales/v3/sales"
)

func main() {}
