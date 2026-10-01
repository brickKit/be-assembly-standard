import importlib.util
import pathlib
import subprocess
import sys
import textwrap

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "docs-boundary.py"


def run(root: pathlib.Path) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPT), "--root", str(root)],
                          capture_output=True, text=True)


def write(root: pathlib.Path, rel: str, body: str) -> None:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(textwrap.dedent(body), encoding="utf-8")


def test_clean_tree_passes(tmp_path):
    write(tmp_path, "AGENTS.md", "[ok](docs/decisions/0001-x.md)\n")
    write(tmp_path, "docs/decisions/0001-x.md", "# x\n")
    write(tmp_path, "dev/plan.md", "[可以链接任何地方](../archive/pre-v1/README.md)\n")
    r = run(tmp_path)
    assert r.returncode == 0, r.stdout + r.stderr


def test_inline_link_into_dev_fails(tmp_path):
    write(tmp_path, "AGENTS.md", "see [plan](dev/phase-06/plan.md)\n")
    r = run(tmp_path)
    assert r.returncode == 1
    assert "AGENTS.md:1" in r.stdout


def test_relative_parent_link_into_archive_fails(tmp_path):
    write(tmp_path, "docs/conventions/testing.md", "[old](../../archive/pre-v1/docs/x.md#a)\n")
    r = run(tmp_path)
    assert r.returncode == 1
    assert "docs/conventions/testing.md:1" in r.stdout


def test_reference_style_and_angle_brackets_fail(tmp_path):
    write(tmp_path, "README.zh.md", "[a][r]\n\n[r]: dev/x.md\n<archive/pre-v1/README.md>\n")
    r = run(tmp_path)
    assert r.returncode == 1
    assert "README.zh.md:3" in r.stdout
    assert "README.zh.md:4" in r.stdout


def test_component_docs_are_checked(tmp_path):
    write(tmp_path, "components/mdm/customer/BRICKKIT.md", "[x](../../../dev/a.md)\n")
    r = run(tmp_path)
    assert r.returncode == 1
    assert "components/mdm/customer/BRICKKIT.md:1" in r.stdout


def test_code_blocks_and_absolute_urls_are_ignored(tmp_path):
    write(tmp_path, "AGENTS.md", "```\n[x](dev/a.md)\n```\n[gh](https://github.com/x/dev/a.md)\n`dev/a.md`\n")
    r = run(tmp_path)
    assert r.returncode == 0, r.stdout
