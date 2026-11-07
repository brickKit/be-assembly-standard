"""authz-keys-check.py: the cells' authorization tables agree with the components' definitions."""
import importlib.util
import pathlib

import pytest

spec = importlib.util.spec_from_file_location(
    "authz_keys_check", pathlib.Path(__file__).resolve().parents[1] / "authz-keys-check.py")
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

DEFINED = {"erp/credit": {"resource_type": {"erp.credit.limit"}, "permission": {"erp.credit.limit.read"}}}


def test_equal_sets_pass():
    assert check.compare({"erp/credit": {k: set(v) for k, v in DEFINED["erp/credit"].items()}}, DEFINED) == []


def test_a_defined_key_missing_from_the_table_fails():
    table = {"erp/credit": {"resource_type": {"erp.credit.limit"}, "permission": set()}}
    assert check.compare(table, DEFINED) == [
        "erp/credit: permission erp.credit.limit.read is defined but missing from the suite's table"]


def test_a_table_key_not_defined_fails():
    table = {"erp/credit": {"resource_type": {"erp.credit.limit", "erp.credit.ghost"},
                            "permission": {"erp.credit.limit.read"}}}
    assert check.compare(table, DEFINED) == [
        "erp/credit: resource_type erp.credit.ghost is in the suite's table but not defined"]


def test_a_component_missing_from_the_tables_and_a_stale_entry_fail():
    out = check.compare({"erp/old": {"resource_type": set(), "permission": set()}}, DEFINED)
    assert out == ["erp/credit: defines resources but is not in the suite's tables",
                   "erp/old: in the suite's tables but not a rebuilt component"]


def test_the_tables_are_read_as_literals(tmp_path):
    cells = tmp_path / "tools/be-acceptance/conformance/cells"
    cells.mkdir(parents=True)
    (cells / "prepare.py").write_text(
        "import asyncpg\n"
        "INFRA_KEYS = {'infra/a': {'resource_type': ['a.x'], 'permission': ['a.x.read']}}\n"
        "MDM_KEYS: dict = {}\n"
        "ERP_KEYS = {}\n")
    assert check.tables(tmp_path) == {"infra/a": {"resource_type": {"a.x"}, "permission": {"a.x.read"}}}


def test_a_missing_table_stops_the_check(tmp_path):
    cells = tmp_path / "tools/be-acceptance/conformance/cells"
    cells.mkdir(parents=True)
    (cells / "prepare.py").write_text("INFRA_KEYS = {}\nMDM_KEYS = {}\n")
    with pytest.raises(SystemExit, match="ERP_KEYS"):
        check.tables(tmp_path)
