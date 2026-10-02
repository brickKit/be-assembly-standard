"""teardown-sync.py 的测试：直接 `python3 infra/scripts/tests/test_teardown_sync.py` 运行（不依赖 pytest）。"""
import pathlib
import subprocess
import sys
import tempfile
import traceback

import yaml

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "teardown-sync.py"

DEPLOY = """\
# deploy.yaml — how this project is deployed.
target: docker # docker | podman | k8s

vars:
  PG_HOST: other-host

components:
  - id: mdm/customer
  - id: be/go-core
    members:
      - id: mdm/product
      - id: erp/sales
        skipWaitFor: [crm/opportunity]
  - id: infra/print
    mode: disable
"""

TEARDOWN_HEADER = """\
# 拆回验证专用部署文件：配合 --ignore-shells 使用，所有成员都按独立组件部署。
# 用 -f 指定时只读这一份文件、忽略本地模式。
"""

TEARDOWN_STALE = TEARDOWN_HEADER + """\
target: podman
vars:
  PG_HOST: x
components:
  - id: mdm/customer
"""


def make(tmp: pathlib.Path, teardown: str | None = TEARDOWN_STALE, deploy: str = DEPLOY) -> pathlib.Path:
    (tmp / "deploy.yaml").write_text(deploy, encoding="utf-8")
    if teardown is not None:
        (tmp / "deploy.teardown.yaml").write_text(teardown, encoding="utf-8")
    return tmp


def run(root: pathlib.Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPT), "--root", str(root), *args],
                          capture_output=True, text=True)


def load(p: pathlib.Path) -> dict:
    return yaml.safe_load(p.read_text(encoding="utf-8"))


def test_sync_copies_components_and_target_drops_vars(tmp):
    root = make(tmp)
    r = run(root)
    assert r.returncode == 0, r.stdout + r.stderr
    t, d = load(root / "deploy.teardown.yaml"), load(root / "deploy.yaml")
    assert t["target"] == d["target"] == "docker", t
    assert t["components"] == d["components"], t           # 外壳 members 嵌套原样
    assert t["components"][1]["members"][1]["skipWaitFor"] == ["crm/opportunity"]
    assert "vars" not in t, t


def test_header_comments_preserved(tmp):
    root = make(tmp)
    run(root)
    assert (root / "deploy.teardown.yaml").read_text(encoding="utf-8").startswith(TEARDOWN_HEADER)


def test_check_detects_drift_and_does_not_write(tmp):
    root = make(tmp)
    before = (root / "deploy.teardown.yaml").read_text(encoding="utf-8")
    r = run(root, "--check")
    assert r.returncode == 1, r.stdout + r.stderr
    assert "be/go-core" in r.stdout, r.stdout                 # 打印差异
    assert (root / "deploy.teardown.yaml").read_text(encoding="utf-8") == before


def test_check_passes_after_sync_and_sync_is_idempotent(tmp):
    root = make(tmp)
    run(root)
    after = (root / "deploy.teardown.yaml").read_text(encoding="utf-8")
    r = run(root, "--check")
    assert r.returncode == 0, r.stdout + r.stderr
    r2 = run(root)
    assert r2.returncode == 0
    assert (root / "deploy.teardown.yaml").read_text(encoding="utf-8") == after


def test_check_flags_vars_only_difference(tmp):
    root = make(tmp)
    run(root)
    p = root / "deploy.teardown.yaml"
    p.write_text(p.read_text(encoding="utf-8") + "vars:\n  PG_HOST: y\n", encoding="utf-8")
    r = run(root, "--check")
    assert r.returncode == 1, r.stdout + r.stderr


def test_empty_components(tmp):
    root = make(tmp, deploy="target: docker\n\ncomponents: []\n")
    r = run(root)
    assert r.returncode == 0, r.stdout + r.stderr
    assert load(root / "deploy.teardown.yaml")["components"] == []


def test_missing_teardown_is_created(tmp):
    root = make(tmp, teardown=None)
    r = run(root)
    assert r.returncode == 0, r.stdout + r.stderr
    t = load(root / "deploy.teardown.yaml")
    assert t["components"] == load(root / "deploy.yaml")["components"]
    assert (root / "deploy.teardown.yaml").read_text(encoding="utf-8").startswith("#")


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
