# C6 P5 (after the consistency exam): crm/opportunity 3.0.1 checks the funnel's owner filter's form.
TITLE = "crm/opportunity 3.0.1: the funnel's owner filter"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOFLAGS": "-mod=mod", "GOWORK": "off"}
MUTANTS = [("internal/forecast/funnel.go", 'QueryFilters(c, []string{"legal_entity_id", "owner_id"}', 'QueryFilters(c, []string{"legal_entity_id"}',
            "funnel: an owner filter of the wrong form is not refused")]
