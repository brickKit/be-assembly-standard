TITLE = "erp/purchase 3.0.0 (C2 P3f): the system surface (MatchService, FactService) and the recovery presence"
BUILD = ["go", "vet", "-tags", "integration", "./..."]
TEST = ["go", "test", "-count=1", "-tags", "integration", "./itest/"]
ENV = {"GOWORK": "off"}
# seen red before the change: MatchService answered UNIMPLEMENTED
B = "internal/matchbasis/matchbasis.go"
F = "internal/facts/facts.go"
C = "purchase/checks.go"
MUTANTS = [
    ("purchase/module.go", '		"Basis": {Operation: core.OpSysRead, Callers: []string{core.Finance}}})',
     '		"Basis": {Operation: core.OpSysRead, Callers: []string{grpcx.AnyComponent}}})', "the match basis for erp/finance only"),
    (B, "				WHERE r.origin_movement_id = mv.movement_id AND r.state = 'posted'), 0))::text",
     "				WHERE r.origin_movement_id = mv.movement_id), 0))::text", "only posted returns are returned"),
    (B, '	if in.GetOrderId() != "" && len(out.Lines) == 0 {\n			return core.NotFound("order")\n		}',
     '	if false {\n			return core.NotFound("order")\n		}', "an order not known is NOT_FOUND"),
    (B, "			WHERE ($1::uuid IS NOT NULL AND l.order_id = $1::uuid) OR l.id = ANY($2::uuid[])",
     "			WHERE ($1::uuid IS NOT NULL AND l.order_id = $1::uuid) OR (l.id = ANY($2::uuid[]) AND l.kind = 'goods')",
     "the lines asked, every kind"),
    (F, '			out.Facts = append(out.Facts, &purchasev3.Fact{FactId: id})', '			_ = id', "a fact not known answers with no type"),
    (C, "		rows, err := tx.Query(ctx, `SELECT id::text FROM acceptance WHERE id::text = ANY($1)`, ids)",
     "		rows, err := tx.Query(ctx, `SELECT id::text FROM acceptance WHERE false AND id::text = ANY($1)`, ids)",
     "an acceptance is present as a receipt"),
    (C, '	c.Presence(core.Policies, recovery.TablePresence("purchase_policy", "legal_entity_id", "version"))', '',
     "the policy's presence"),
]
