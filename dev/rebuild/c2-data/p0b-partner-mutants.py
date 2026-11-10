TITLE = "mdm/partner 3.0.39 (C2 P0b): the supplier role"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
# seen red before the change (the test written first): purchase answered CAPABILITY_UNSUPPORTED, the route 501
R = "internal/roles/roles.go"
MUTANTS = [
    (R, "func PutSupplierRole(m *core.Base, c *httpx.Context) error { return putRole(m, c, \"supplier\") }",
     "func PutSupplierRole(m *core.Base, c *httpx.Context) error { return putRole(m, c, \"customer\") }",
     "the supplier route opens the supplier role"),
    (R, "func SupplierRoleState(m *core.Base, c *httpx.Context) error { return roleState(m, c, \"supplier\") }",
     "func SupplierRoleState(m *core.Base, c *httpx.Context) error { return roleState(m, c, \"customer\") }",
     "the supplier's state is its own"),
    (R, "	case \"purchase\":\n		return \"supplier\", true", "	case \"purchase\":\n		return \"customer\", true",
     "purchase needs the supplier role"),
]
