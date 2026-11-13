"""audit-target-check.py: what was done never goes in an audit target (C10 retro R6)."""
import importlib.util
import pathlib

spec = importlib.util.spec_from_file_location("audit_target_check",
                                              pathlib.Path(__file__).resolve().parents[1] / "audit-target-check.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def write(root: pathlib.Path, rel: str, text: str) -> None:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


def test_a_map_in_the_target_is_named(tmp_path):
    """2026-11-13: integration/im-dingtalk 3.0.2 wrote bound or ended there; the audit kept neither."""
    write(tmp_path, "components/integration/im-dingtalk/internal/bindings/bindings.go",
          'x := audit.Record{Target: audit.TargetOf(core.Bindings, principal, map[string]any{"change": what})}\n')
    write(tmp_path, "components/infra/attachment/internal/x/x.go",
          'y := audit.TargetOf("infra.attachment", a.ID,\n\tmap[string]any{"content_version": v})\n')
    assert mod.check(tmp_path) == [
        "components/infra/attachment/internal/x/x.go:1: TargetOf with a map: what was done goes in Changes",
        "components/integration/im-dingtalk/internal/bindings/bindings.go:1: TargetOf with a map: what was done goes in Changes"]


def test_the_object_or_nil_passes(tmp_path):
    write(tmp_path, "components/erp/sales/internal/core/rules.go",
          'a := audit.TargetOf(typ, id, after)\nb := audit.TargetOf(core.X, id(p), nil)\nc := audit.TargetOf(t, i, f(x))\n')
    write(tmp_path, "components/erp/sales/internal/core/rules_test.go", 'audit.TargetOf(t, i, map[string]any{"a": 1})\n')
    assert mod.check(tmp_path) == []
