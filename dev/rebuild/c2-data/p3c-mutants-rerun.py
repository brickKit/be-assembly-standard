TITLE = "erp/purchase 3.0.0 (C2 P3c): rerun of the two survivors (another product in the same unit; a supplier with no orders)"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
# seen red before the change: the order routes answered CAPABILITY_UNSUPPORTED
O = "internal/orders/orders.go"
L = "internal/orders/lifecycle.go"
N = "internal/orders/lines.go"
Q = "internal/requisitions/ordering.go"
MUTANTS = [
    ('internal/requisitions/ordering.go', '\t\t\tif r.LegalEntityID != legalEntity || l.ProductID != t.ProductID || l.Unit != t.Unit {', '\t\t\tif r.LegalEntityID != legalEntity || l.Unit != t.Unit {', 'PR06: a requisition line of the same product'),
    ('internal/orders/orders.go', '\tfor _, p := range []string{"legal_entity_id", "supplier_id", "owner_id", "department_id", "state"} {', '\tfor _, p := range []string{"legal_entity_id", "owner_id", "department_id", "state"} {', 'the list filters by supplier'),
]
