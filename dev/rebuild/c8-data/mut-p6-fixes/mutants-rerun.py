TITLE = "infra/notification 3.0.2: the consistency exam's fixes (C8 P6), the rerun"
BUILD = ["go", "vet", "-tags", "integration", "./itest/"]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off", "GOFLAGS": "-mod=mod"}
MUTANTS = [
    ('internal/delivery/delivery.go', '\t\tif had {\n\t\t\tcontinue\n\t\t}\n', '', 'M3 a position is expanded once'),
]
