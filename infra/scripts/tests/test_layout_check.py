"""layout-check.py: a rebuilt Go component is laid out by business module, with a description in every layer."""
import importlib.util
import pathlib

spec = importlib.util.spec_from_file_location("layout_check",
                                              pathlib.Path(__file__).resolve().parents[1] / "layout-check.py")
layout_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layout_check)


def agents(files: list[str], extra: str = "") -> str:
    rows = "".join(f"| `{f}` | what it does |\n" for f in files)
    return f"# a layer\n\nOne sentence.\n{extra}\n## 文件\n\n| 文件 | 内容 |\n| --- | --- |\n{rows}\n## 测试\n\nWhere.\n"


def layer(d: pathlib.Path, files: list[str], extra: str = "") -> None:
    d.mkdir(parents=True, exist_ok=True)
    for f in files:
        (d / f).write_text("package x\n")
    (d / "AGENTS.md").write_text(agents(files, extra))
    (d / "CLAUDE.md").write_text("@AGENTS.md\n")


def component(root: pathlib.Path) -> pathlib.Path:
    d = root / "components/erp/sales"
    d.mkdir(parents=True)
    (d / "component.yaml").write_text("apiVersion: v1\nmetadata:\n  id: erp/sales\n  version: 3.0.40\n")
    (d / "go.mod").write_text("module github.com/brickKit/erp-sales/v3\n")
    (d / "main.go").write_text("package main\n\nfunc main() { launcher.Main(sales.Definition()) }\n")
    (d / "AGENTS.md").write_text("# erp/sales\n\n[orders](internal/orders/AGENTS.md) [core](internal/core/AGENTS.md)\n")
    layer(d / "sales", ["definition.go", "module.go", "contract_test.go"])
    (d / "internal").mkdir()
    (d / "internal/AGENTS.md").write_text("# internal\n\n## 模块\n\n| 包 | 一句话 | 依赖 |\n| --- | --- | --- |\n"
                                          "| `orders` | orders | `core` |\n| `core`（共用） | names | — |\n\n## 测试\n")
    (d / "internal/CLAUDE.md").write_text("@AGENTS.md\n")
    layer(d / "internal/orders", ["orders.go", "lifecycle_test.go"])
    layer(d / "internal/core", ["names.go"])
    layer(d / "itest", ["endtoend_integration_test.go"])
    return d


def imports(_d):
    return {"orders": {"core"}, "core": set()}


def test_a_laid_out_component_passes(tmp_path):
    d = component(tmp_path)
    assert layout_check.check("erp/sales", d, imports) == []
    assert [cid for cid, _ in layout_check.components(tmp_path)] == ["erp/sales"]


def test_a_layer_without_its_description_fails(tmp_path):
    d = component(tmp_path)
    (d / "internal/core/CLAUDE.md").unlink()
    (d / "itest/AGENTS.md").unlink()
    errs = layout_check.check("erp/sales", d, imports)
    assert any("internal/core/CLAUDE.md is missing" in e for e in errs), errs
    assert any("itest/AGENTS.md is missing" in e for e in errs), errs


def test_a_file_the_description_does_not_list_fails(tmp_path):
    d = component(tmp_path)
    (d / "internal/orders/archive.go").write_text("package orders\n")
    (d / "internal/core/names.go").unlink()
    (d / "internal/core/rules.go").write_text("package core\n")
    errs = layout_check.check("erp/sales", d, imports)
    assert any("internal/orders/archive.go is not in" in e for e in errs), errs
    assert any("lists names.go, which is not in internal/core/" in e for e in errs), errs


def test_business_in_the_entry_package_fails(tmp_path):
    d = component(tmp_path)
    (d / "sales/pricing.go").write_text("package sales\n")
    (d / "sales/AGENTS.md").write_text(agents(["definition.go", "module.go", "contract_test.go", "pricing.go"]))
    errs = layout_check.check("erp/sales", d, imports)
    assert errs == ["erp/sales: sales/pricing.go: the entry package only assembles (checks.go, definition.go, "
                    "module.go, services.go); business goes under internal/"]


def test_an_integration_test_outside_itest_fails(tmp_path):
    d = component(tmp_path)
    (d / "internal/orders/orders_integration_test.go").write_text("package orders\n")
    (d / "internal/orders/AGENTS.md").write_text(agents(["orders.go", "lifecycle_test.go", "orders_integration_test.go"]))
    errs = layout_check.check("erp/sales", d, imports)
    assert errs == ["erp/sales: internal/orders/orders_integration_test.go: integration tests are in itest/"]


def test_a_dependency_the_module_table_does_not_say_fails(tmp_path):
    d = component(tmp_path)
    errs = layout_check.check("erp/sales", d, lambda _d: {"orders": {"core", "ledger"}, "core": set()})
    assert errs == ["erp/sales: internal/AGENTS.md says orders depends on ['core'], it imports ['core', 'ledger']"]


def test_a_module_missing_from_the_maps_fails(tmp_path):
    d = component(tmp_path)
    layer(d / "internal/ledger", ["ledger.go"])
    errs = layout_check.check("erp/sales", d, lambda _d: {"orders": {"core"}, "core": set(), "ledger": set()})
    assert "erp/sales: internal/ledger has no row in internal/AGENTS.md's 模块" in errs
    assert "erp/sales: AGENTS.md does not link internal/ledger/AGENTS.md" in errs
