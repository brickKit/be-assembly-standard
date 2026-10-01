import pathlib
import subprocess
import sys
import textwrap

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "docs-mirror.py"


def run(root: pathlib.Path) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPT), "--root", str(root)],
                          capture_output=True, text=True)


def write(root: pathlib.Path, rel: str, body: str) -> None:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(textwrap.dedent(body), encoding="utf-8")


def pair(root: pathlib.Path, sub: str, en_body: str = "# T\n\n## A\n", zh_body: str = "# T\n\n## 甲\n") -> None:
    """在两棵树里各写一份 sub，第一行是正确的语言切换行。"""
    depth = sub.count("/") + 1
    up = "../" * depth
    base = sub.rsplit("/", 1)[-1]
    write(root, f"docs/en/{sub}", f"[English]({base}) · [中文]({up}zh/{sub})\n\n" + en_body)
    write(root, f"docs/zh/{sub}", f"[English]({up}en/{sub}) · [中文]({base})\n\n" + zh_body)


def test_clean_mirror_passes(tmp_path):
    pair(tmp_path, "README.md")
    pair(tmp_path, "01-conventions/02-backend.md")
    pair(tmp_path, "02-decisions/01-architecture/0001-x.md")
    r = run(tmp_path)
    assert r.returncode == 0, r.stdout + r.stderr


def test_no_docs_tree_passes(tmp_path):
    write(tmp_path, "AGENTS.md", "# x\n")
    r = run(tmp_path)
    assert r.returncode == 0, r.stdout + r.stderr


def test_file_only_in_en_fails(tmp_path):
    pair(tmp_path, "README.md")
    write(tmp_path, "docs/en/03-seed-data.md", "[English](03-seed-data.md) · [中文](../zh/03-seed-data.md)\n")
    r = run(tmp_path)
    assert r.returncode == 1
    assert "docs/en/03-seed-data.md: " in r.stdout
    assert "docs/zh/03-seed-data.md" in r.stdout


def test_file_only_in_zh_fails(tmp_path):
    pair(tmp_path, "README.md")
    write(tmp_path, "docs/zh/01-conventions/09-x.md", "[English](../../en/01-conventions/09-x.md) · [中文](09-x.md)\n")
    r = run(tmp_path)
    assert r.returncode == 1
    assert "docs/zh/01-conventions/09-x.md: " in r.stdout


def test_different_h2_count_fails(tmp_path):
    pair(tmp_path, "01-conventions/06-testing.md",
         en_body="# T\n\n## A\n\n## B\n", zh_body="# T\n\n## 甲\n")
    r = run(tmp_path)
    assert r.returncode == 1
    assert "docs/en/01-conventions/06-testing.md: " in r.stdout
    assert "2" in r.stdout and "1" in r.stdout


def test_h2_inside_code_fence_and_deeper_headings_do_not_count(tmp_path):
    pair(tmp_path, "README.md",
         en_body="# T\n\n## A\n\n```\n## not a heading\n```\n\n### deeper\n",
         zh_body="# T\n\n## 甲\n")
    r = run(tmp_path)
    assert r.returncode == 0, r.stdout


def test_first_line_without_counterpart_link_fails(tmp_path):
    pair(tmp_path, "README.md")
    write(tmp_path, "docs/zh/README.md", "# 没有语言切换行\n\n## 甲\n")
    r = run(tmp_path)
    assert r.returncode == 1
    assert "docs/zh/README.md: " in r.stdout


def test_first_line_link_that_does_not_resolve_to_counterpart_fails(tmp_path):
    pair(tmp_path, "01-conventions/02-backend.md")
    # 少了一层 ../，指到 docs/en/zh/... 这个不存在的文件
    write(tmp_path, "docs/en/01-conventions/02-backend.md",
          "[English](02-backend.md) · [中文](../zh/01-conventions/02-backend.md)\n\n# T\n\n## A\n")
    r = run(tmp_path)
    assert r.returncode == 1
    assert "docs/en/01-conventions/02-backend.md: " in r.stdout


def test_first_line_link_to_another_existing_file_fails(tmp_path):
    pair(tmp_path, "README.md")
    pair(tmp_path, "03-seed-data.md")
    write(tmp_path, "docs/en/03-seed-data.md",
          "[English](03-seed-data.md) · [中文](../zh/README.md)\n\n# T\n\n## A\n")
    r = run(tmp_path)
    assert r.returncode == 1
    assert "docs/en/03-seed-data.md: " in r.stdout
