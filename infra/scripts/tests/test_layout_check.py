"""layout-check.py: a rebuilt Go or Python component is laid out by business module, with a description in every
layer."""
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
        (d / f).write_text("" if f.endswith(".py") else "package x\n")
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


def py_component(root: pathlib.Path) -> pathlib.Path:
    d = root / "components/infra/print"
    d.mkdir(parents=True)
    (d / "component.yaml").write_text("apiVersion: v1\nmetadata:\n  id: infra/print\n  version: 3.0.15\n")
    (d / "pyproject.toml").write_text('[tool.hatch.build.targets.wheel]\npackages = ["infra_print"]\n')
    (d / "AGENTS.md").write_text("# infra/print\n\n[templates](infra_print/templates/AGENTS.md) "
                                 "[rendering](infra_print/rendering/AGENTS.md)\n")
    table = ("\n## 模块\n\n| 包 | 一句话 | 依赖 |\n| --- | --- | --- |\n| `rendering` | renders | `templates` |\n"
             "| `templates` | versions | — |\n")
    for f, body in {"__init__.py": "", "__main__.py": "", "module.py": "from infra_print.rendering import render\n"}.items():
        (d / "infra_print").mkdir(exist_ok=True)
        (d / "infra_print" / f).write_text(body)
    (d / "infra_print/AGENTS.md").write_text(agents(["__init__.py", "__main__.py", "module.py"], table).replace(".go", ".py"))
    (d / "infra_print/CLAUDE.md").write_text("@AGENTS.md\n")
    layer(d / "infra_print/templates", ["__init__.py", "store.py"])
    layer(d / "infra_print/rendering", ["__init__.py", "render.py"])
    (d / "infra_print/rendering/render.py").write_text("from infra_print.templates.store import Store\n")
    layer(d / "itest", ["test_print_integration.py"])
    (d / "itest/test_print_integration.py").write_text("import pytest\n\npytestmark = pytest.mark.integration\n")
    (d / "tests").mkdir()
    (d / "tests/test_rendering.py").write_text("def test_x():\n    pass\n")
    return d


def test_a_laid_out_python_component_passes(tmp_path):
    d = py_component(tmp_path)
    assert layout_check.check("infra/print", d) == []
    assert [cid for cid, _ in layout_check.components(tmp_path)] == ["infra/print"]


def test_a_python_component_out_of_its_layout_fails(tmp_path):
    d = py_component(tmp_path)
    (d / "infra_print/renderer.py").write_text("")  # business in the entry package
    (d / "tests/test_print_integration.py").write_text("import pytest\n\n@pytest.mark.integration\ndef test_y():\n    pass\n")
    (d / "infra_print/templates/store.py").write_text("from infra_print.rendering import render\n")  # a dependency the table does not say
    (d / "infra_print/rendering/CLAUDE.md").unlink()
    errs = layout_check.check("infra/print", d)
    assert any("infra_print/renderer.py: the entry package only assembles" in e for e in errs), errs
    assert any("tests/test_print_integration.py: integration tests are in itest/" in e for e in errs), errs
    assert any("says templates depends on [], it imports ['rendering']" in e for e in errs), errs
    assert any("infra_print/rendering/CLAUDE.md is missing" in e for e in errs), errs
    assert any("infra_print/renderer.py is not in infra_print/AGENTS.md" in e for e in errs), errs
