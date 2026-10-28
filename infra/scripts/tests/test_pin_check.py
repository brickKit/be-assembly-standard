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
