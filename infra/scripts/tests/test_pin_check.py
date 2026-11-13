"""pin-check.py: every exact reference to a rebuilt component names its current version."""
import importlib.util
import pathlib

spec = importlib.util.spec_from_file_location("pin_check", pathlib.Path(__file__).resolve().parents[1] / "pin-check.py")
pin_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pin_check)


def component(root: pathlib.Path, rel: str, cid: str, version: str, body: str = "", gomod: str = "",
              dockerfile: str = "") -> None:
    d = root / rel
    d.mkdir(parents=True)
    (d / "component.yaml").write_text(f"apiVersion: v1\nmetadata:\n  id: {cid}\n  version: {version}\n{body}")
    if gomod:
        (d / "go.mod").write_text(gomod)
    if dockerfile:
        (d / "Dockerfile").write_text(dockerfile)


def tree(root: pathlib.Path, probe_pin: str, shell_pin: str) -> None:
    component(root, "tools/be-acceptance/probes/go", "test/probe-go", "3.2.21",
              gomod="module github.com/brickKit/be-acceptance/probes/go/v3\n")
    component(root, "tools/be-acceptance/probes/go2", "test/probe-go2", "3.2.21", dockerfile=(
        "FROM golang AS build\n"
        f"RUN go install -trimpath github.com/brickKit/be-acceptance/probes/go/v3@v{probe_pin}\n"))
    component(root, "components/erp/sales", "erp/sales", "3.0.12",
              gomod="module github.com/brickKit/erp-sales/v3\n")
    component(root, "shell/be/go-core", "be/go-core", "3.0.34",
              body="shell:\n  members:\n    - test/probe-go@3.2.21\n    - erp/sales@3.0.12\n",
              gomod=("module github.com/brickKit/be-go-core/v3\n\nrequire (\n"
                     f"\tgithub.com/brickKit/be-acceptance/probes/go/v3 v{shell_pin}\n"
                     "\tgithub.com/brickKit/erp-sales/v3 v3.0.12\n)\n"))


def test_current_pins_pass(tmp_path):
    tree(tmp_path, "3.2.21", "3.2.21")
    assert pin_check.check(tmp_path) == []


def test_a_dockerfile_installing_an_older_module_is_stale(tmp_path):
    """2026-10-28: probe-go2 3.2.20's image installed the probe module at v3.2.19 and came up unhealthy."""
    tree(tmp_path, "3.2.20", "3.2.21")
    assert pin_check.check(tmp_path) == [
        "tools/be-acceptance/probes/go2/Dockerfile: test/probe-go v3.2.20, current 3.2.21"]


def test_a_shell_requiring_an_older_module_below_the_repository_root_is_stale(tmp_path):
    tree(tmp_path, "3.2.21", "3.2.20")
    assert pin_check.check(tmp_path) == ["shell/be/go-core/go.mod: test/probe-go v3.2.20, current 3.2.21"]


def sdk_gomod(root: pathlib.Path, rel: str, version: str, indirect: bool = False) -> None:
    d = root / rel
    d.mkdir(parents=True, exist_ok=True)
    tail = " // indirect" if indirect else ""
    (d / "go.mod").write_text(f"module example.com/{rel}\n\nrequire github.com/brickKit/be-sdk-go/v3 {version}{tail}\n")


def sdk_tree(root: pathlib.Path, ops: str) -> None:
    sdk_gomod(root, "components/erp/sales", "v3.0.0-alpha.117")
    sdk_gomod(root, "shell/be/go-core", "v3.0.0-alpha.117")
    sdk_gomod(root, "tools/be-acceptance/probes/go", "v3.0.0-alpha.117")
    sdk_gomod(root, "tools/be-ops", ops)


def test_one_sdk_version_passes(tmp_path):
    sdk_tree(tmp_path, "v3.0.0-alpha.117")
    assert pin_check.one_sdk(tmp_path) == []


def test_a_deployed_tool_left_on_an_older_sdk_fails(tmp_path):
    sdk_tree(tmp_path, "v3.0.0-alpha.116")
    out = pin_check.one_sdk(tmp_path)
    assert len(out) == 1 and "tools/be-ops/go.mod" in out[0] and "v3.0.0-alpha.116" in out[0]


def test_the_frozen_shell_and_test_fixtures_do_not_count(tmp_path):
    sdk_tree(tmp_path, "v3.0.0-alpha.117")
    sdk_gomod(tmp_path, "shell/be/go-backoffice", "v3.0.0-alpha.50")
    sdk_gomod(tmp_path, "tools/be-sdk-python/tests/interop/gochain", "v3.0.0-alpha.73")
    sdk_gomod(tmp_path, "components/mdm/org", "v3.0.0-alpha.90", indirect=True)
    assert pin_check.one_sdk(tmp_path) == []


def test_the_edge_tests_count(tmp_path):
    sdk_tree(tmp_path, "v3.0.0-alpha.117")
    sdk_gomod(tmp_path, "tools/be-edge/tests", "v3.0.0-alpha.56")
    out = pin_check.one_sdk(tmp_path)
    assert len(out) == 1 and "tools/be-edge/tests/go.mod" in out[0]


def py_member(root: pathlib.Path, rel: str, tag: str) -> None:
    d = root / rel
    d.mkdir(parents=True, exist_ok=True)
    (d / "pyproject.toml").write_text(f'[project]\nname = "m"\nversion = "3.0.0"\ndependencies = ["be-sdk>={tag[1:]}"]\n'
                                      f'[tool.uv.sources]\nbe-sdk = {{ git = "https://x/be-sdk-python", tag = "{tag}" }}\n')


def py_shell(root: pathlib.Path, rel: str, tag: str) -> None:
    d = root / rel
    d.mkdir(parents=True, exist_ok=True)
    (d / "pyproject.toml").write_text(f'[project]\nname = "s"\nversion = "3.0.0"\ndependencies = ["be-sdk"]\n'
                                      f'[tool.uv]\noverride-dependencies = ["be-sdk @ git+https://x/be-sdk-python@{tag}"]\n'
                                      f'[tool.uv.sources]\nbe-sdk = {{ git = "https://x/be-sdk-python", tag = "{tag}" }}\n')


def test_one_python_sdk_passes(tmp_path):
    py_member(tmp_path, "components/infra/print", "v3.0.0a52")
    py_member(tmp_path, "tools/be-acceptance/probes/py", "v3.0.0a52")
    py_shell(tmp_path, "shell/be/py-render", "v3.0.0a52")
    assert pin_check.one_python_sdk(tmp_path) == []


def test_a_python_member_on_an_older_sdk_fails(tmp_path):
    py_member(tmp_path, "components/infra/print", "v3.0.0a48")
    py_member(tmp_path, "tools/be-acceptance/probes/py", "v3.0.0a51")
    py_shell(tmp_path, "shell/be/py-render", "v3.0.0a51")
    out = pin_check.one_python_sdk(tmp_path)
    assert len(out) == 1 and "components/infra/print/pyproject.toml" in out[0] and "v3.0.0a48" in out[0]


def test_a_shell_whose_override_differs_from_its_source_fails(tmp_path):
    py_member(tmp_path, "tools/be-acceptance/probes/py", "v3.0.0a52")
    d = tmp_path / "shell/be/py-render"
    d.mkdir(parents=True)
    (d / "pyproject.toml").write_text('[project]\nname = "s"\nversion = "3.0.0"\ndependencies = ["be-sdk"]\n'
                                      '[tool.uv]\noverride-dependencies = ["be-sdk @ git+https://x/be-sdk-python@v3.0.0a51"]\n'
                                      '[tool.uv.sources]\nbe-sdk = { git = "https://x/be-sdk-python", tag = "v3.0.0a52" }\n')
    out = pin_check.one_python_sdk(tmp_path)
    assert any("override" in o for o in out), out


def test_a_go_component_without_go_module_release_is_named(tmp_path):
    """2026-11-13: integration/im-dingtalk 3.0.0 was released with only the bare tag 3.0.0, no v3.0.0 for the shells."""
    component(tmp_path, "components/integration/im-dingtalk", "integration/im-dingtalk", "3.0.0",
              gomod="module github.com/brickKit/integration-im-dingtalk/v3\n")
    component(tmp_path, "components/erp/sales", "erp/sales", "3.0.12", body="release:\n  goModule: true\n",
              gomod="module github.com/brickKit/erp-sales/v3\n")
    component(tmp_path, "components/infra/print", "infra/print", "3.0.3")  # no go.mod: not a Go module
    component(tmp_path, "shell/be/go-infra", "be/go-infra", "3.0.93", body="shell:\n  members: []\n",
              gomod="module github.com/brickKit/be-go-infra/v3\n")  # a shell: an image, not a dependency
    component(tmp_path, "components/old/thing", "old/thing", "2.1.0", gomod="module example.com/old\n")  # not rebuilt
    assert pin_check.go_module_release(tmp_path) == [
        "components/integration/im-dingtalk/component.yaml: a Go module without release.goModule: true "
        "(brickkit release tags only the bare version; the shells cannot fetch it)"]
