TITLE = "be-sdk-go alpha.116 (T11a): a destroyed unit's members are gone from the decision on (P15.22, P15.24, P15.29)"
BUILD = ["go", "vet", "-tags", "integration", "./tiering/"]
TEST = ["bash", "-c", ". ../../dev/rebuild/experiment-scripts/itenv.sh > /dev/null 2>&1 && go test -count=1 -tags integration "
        "-run 'TestADestroyedRecordIsGoneFromTheDecisionOn|TestTheDestructionConditions' ./tiering/"]
MUTANTS = [
    ("tiering/reads.go", "\tif err == nil && u.state == StateDestroyed {\n\t\treturn Aggregate{}, false, errs.New(errs.ReasonNotFound, \"the record was destroyed at the end of its retention\")\n\t}\n",
     "", "a destroyed member is not found by key"),
    ("tiering/reads.go", "AND ((u.route <> 'online' AND u.route_version <= %d) OR u.state = 'destroyed'))\",",
     "AND ((u.route <> 'online' AND u.route_version <= %d) OR false))\",", "an online list leaves a destroyed unit's members out"),
]
