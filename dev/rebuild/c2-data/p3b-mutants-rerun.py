TITLE = "erp/purchase 3.0.0 (C2 P3b): rerun of the two survivors (a stale version above 0; a reader of another legal entity)"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
# seen red before the change: the routes answered CAPABILITY_UNSUPPORTED
R = "internal/requisitions/requisitions.go"
L = "internal/requisitions/lifecycle.go"
P = "internal/policies/policies.go"
MUTANTS = [
    ('internal/policies/policies.go', 'updated_at = now() WHERE legal_entity_id = $1 AND version = $4`', 'updated_at = now() WHERE legal_entity_id = $1 AND $4::bigint IS NOT NULL`', 'a policy changes on its version'),
    ('internal/requisitions/requisitions.go', '\tif _, _, err := core.Check(c, core.OpReqRead, reqFacts(r)); err != nil {', '\tif _, _, err := core.Check(c, core.OpReqRead, nil); err != nil {', 'what one may not see does not exist'),
]
