"""verify-component.sh --deploy-only 的测试（只算闭包、生成 deploy.verify.yaml，不碰 Docker）。
直接 `python3 infra/scripts/tests/test_verify_deploy.py` 运行（不依赖 pytest）。
"""
import os
import pathlib
import shlex
import subprocess
import sys
import tempfile
import traceback

import yaml

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "verify-component.sh"

# 依赖：sales → customer、product（必需）、notification（可选，未加入项目）；opportunity → customer；
#       iam-casdoor → authz；外壳 be/go-core 托管 customer、sales；print 无关
MANIFESTS = {
    "mdm/customer": {"port": 8080},
    "mdm/product": {"port": 8081},
    "erp/sales": {"port": 8100, "deps": ["mdm/customer@2.0.0", "mdm/product@2.0.0",
                                         {"id": "infra/notification@2.0.0", "optional": True}]},
    "crm/opportunity": {"port": 8110, "deps": ["mdm/customer@2.0.0", {"id": "erp/sales@2.0.0", "optional": True}]},
    "infra/authz": {"port": 8223},
    "infra/iam-casdoor": {"port": 8200, "deps": ["infra/authz@2.0.0"]},
    "infra/print": {"port": 8400},
}


def make(tmp: pathlib.Path, ids, deploy_components, shells=None) -> pathlib.Path:
    shells = shells or {}
    comps = [{"id": i, "version": "2.0.0"} for i in ids] + \
            [{"id": s, "version": "1.0.0", "kind": "shell"} for s in shells]
    (tmp / "brickkit.yaml").write_text(yaml.safe_dump({"project": "t", "components": comps}), encoding="utf-8")
    for cid, spec in MANIFESTS.items():
        m = {"apiVersion": "brickkit/v1", "kind": "Component",
             "metadata": {"id": cid, "version": "2.0.0"},
             "deployment": {"type": "container", "port": spec["port"]}}
        if spec.get("deps"):
            m["dependencies"] = {"components": spec["deps"]}
        p = tmp / "components" / cid / "component.yaml"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(yaml.safe_dump(m), encoding="utf-8")
    for sid, members in shells.items():
        m = {"apiVersion": "brickkit/v1", "kind": "Component", "metadata": {"id": sid, "version": "1.0.0"},
             "shell": {"members": [f"{x}@2.0.0" for x in members]},
             "deployment": {"type": "container", "port": 8090}}
        p = tmp / "shell" / sid / "component.yaml"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(yaml.safe_dump(m), encoding="utf-8")
    (tmp / "deploy.yaml").write_text(yaml.safe_dump({"target": "docker", "vars": {"PG_HOST": "h"},
                                                     "components": deploy_components}), encoding="utf-8")
    return tmp


def run(root: pathlib.Path, cid: str):
    out = root / "deploy.verify.yaml"
    r = subprocess.run(["bash", str(SCRIPT), cid, "--deploy-only", str(out)], capture_output=True, text=True,
                       env={**os.environ, "BE_ROOT": str(root)})
    vars_ = {}
    for line in r.stdout.splitlines():
        k, _, v = line.partition("=")
        vars_[k] = (shlex.split(v) or [""])[0]
    d = yaml.safe_load(out.read_text(encoding="utf-8")) if out.exists() else None
    return r, vars_, d


def modes(d) -> dict:
    out = {}
    for e in d["components"]:
        out[e["id"]] = e.get("mode")
        for m in e.get("members") or []:
            out[f"{e['id']}>{m['id']}"] = m.get("mode")
    return out


ALL = ["mdm/customer", "mdm/product", "erp/sales", "crm/opportunity", "infra/print"]


def test_dependency_target_enabled_rest_disabled(tmp):
    root = make(tmp, ALL, [{"id": i} for i in ALL])
    r, v, d = run(root, "mdm/customer")
    assert r.returncode == 0, r.stdout + r.stderr
    m = modes(d)
    assert m["mdm/customer"] == "enabled", m          # 被依赖的组件不会自己启动：显式 enabled
    for other in ("mdm/product", "erp/sales", "crm/opportunity", "infra/print"):
        assert m[other] == "disable", m
    assert d["vars"] == {"PG_HOST": "h"} and d["target"] == "docker"   # 其余内容原样
    assert v["KEEP_IDS"] == "mdm/customer@2.0.0", v
    assert v["SVC"] == "mdm-customer-2-0-0" and v["PORT"] == "8080" and v["IS_SHELL"] == "0", v


def test_closure_follows_required_and_present_optional(tmp):
    root = make(tmp, ALL, [{"id": i} for i in ALL])
    r, v, d = run(root, "crm/opportunity")
    assert r.returncode == 0, r.stdout + r.stderr
    keep = set(v["KEEP_IDS"].split())
    # opportunity → customer（必需）、sales（可选且在项目里）→ product；notification 不在项目里，不进闭包
    assert keep == {"crm/opportunity@2.0.0", "mdm/customer@2.0.0", "erp/sales@2.0.0", "mdm/product@2.0.0"}, keep
    assert modes(d)["infra/print"] == "disable"


def test_authz_and_iam_always_kept_when_in_project(tmp):
    ids = ALL + ["infra/authz", "infra/iam-casdoor"]
    root = make(tmp, ids, [{"id": i} for i in ids])
    r, v, d = run(root, "mdm/product")
    assert r.returncode == 0, r.stdout + r.stderr
    m = modes(d)
    assert m["infra/authz"] == "enabled" and m["infra/iam-casdoor"] == "enabled", m
    assert m["mdm/customer"] == "disable", m


def test_shell_with_closure_member_kept_whole(tmp):
    deploy = [{"id": "mdm/product"}, {"id": "crm/opportunity"}, {"id": "infra/print"},
              {"id": "be/go-core", "members": [{"id": "mdm/customer"}, {"id": "erp/sales"}]}]
    root = make(tmp, ALL, deploy, shells={"be/go-core": ["mdm/customer", "erp/sales"]})
    r, v, d = run(root, "mdm/customer")
    assert r.returncode == 0, r.stdout + r.stderr
    m = modes(d)
    assert m["be/go-core"] == "enabled", m
    assert m["be/go-core>mdm/customer"] is None and m["be/go-core>erp/sales"] is None, m
    # 外壳里的 sales 必需 product：外壳整个保留，product 也得跑
    assert m["mdm/product"] == "enabled", m
    assert m["crm/opportunity"] == "disable" and m["infra/print"] == "disable", m


def test_disabled_shell_members_disabled_too(tmp):
    deploy = [{"id": "mdm/product"}, {"id": "infra/print"},
              {"id": "be/go-core", "members": [{"id": "mdm/customer"}, {"id": "erp/sales"}]}]
    ids = ["mdm/customer", "mdm/product", "erp/sales", "infra/print"]
    root = make(tmp, ids, deploy, shells={"be/go-core": ["mdm/customer", "erp/sales"]})
    r, v, d = run(root, "infra/print")
    assert r.returncode == 0, r.stdout + r.stderr
    m = modes(d)
    assert m["be/go-core"] == "disable", m
    assert m["be/go-core>mdm/customer"] == "disable" and m["be/go-core>erp/sales"] == "disable", m


def test_shell_target_lists_members(tmp):
    deploy = [{"id": "mdm/product"}, {"id": "infra/print"},
              {"id": "be/go-core", "members": [{"id": "mdm/customer"}, {"id": "erp/sales"}]}]
    ids = ["mdm/customer", "mdm/product", "erp/sales", "infra/print"]
    root = make(tmp, ids, deploy, shells={"be/go-core": ["mdm/customer", "erp/sales"]})
    r, v, d = run(root, "be/go-core")
    assert r.returncode == 0, r.stdout + r.stderr
    assert v["IS_SHELL"] == "1", v
    assert v["MEMBERS"].split() == ["mdm/customer@2.0.0|mdm-customer-2-0-0|8080", "erp/sales@2.0.0|erp-sales-2-0-0|8100"], v
    assert modes(d)["infra/print"] == "disable"


def test_target_not_in_project_fails(tmp):
    root = make(tmp, ["mdm/customer"], [{"id": "mdm/customer"}])
    r, _, _ = run(root, "erp/sales")
    assert r.returncode != 0
    assert "make integrate" in r.stdout + r.stderr


def main() -> int:
    tests = [(n, f) for n, f in sorted(globals().items()) if n.startswith("test_") and callable(f)]
    failed = 0
    for name, fn in tests:
        with tempfile.TemporaryDirectory() as d:
            try:
                fn(pathlib.Path(d))
                print(f"  ok   {name}")
            except Exception:  # noqa: BLE001
                failed += 1
                print(f"  FAIL {name}")
                traceback.print_exc()
    print(f"{len(tests) - failed}/{len(tests)} 通过")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
