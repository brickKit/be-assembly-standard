TITLE = "erp/purchase 3.0.0 (C2 P3e): rerun of the survivor (a quantity over with the amount within)"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
# seen red before the change: the acceptance and return routes answered CAPABILITY_UNSUPPORTED
A = "internal/acceptances/acceptances.go"
R = "internal/returns/returns.go"
MUTANTS = [
    ('internal/acceptances/acceptances.go', '\t\t\t\tAND accepted_qty + $2::numeric <= quantity * (1 + $4::numeric / 100)\n', '', 'PO08: within the ordered quantity'),
]
