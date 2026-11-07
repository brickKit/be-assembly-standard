#!/usr/bin/env python3
"""layout-check: the rebuilt Go components are laid out by business module, with a description in every layer
(docs/zh/01-conventions/05-ai-navigation.md, "组件仓库的标准布局与代码地图" and its "布局检查").

For each component under components/ whose component.yaml is at 3.x and which has a go.mod and a main.go:
  - the entry package (the one main.go runs: launcher.Main(<pkg>.Definition())), internal/, every package under
    internal/ and itest/ each have an AGENTS.md and a CLAUDE.md that is exactly @AGENTS.md;
  - the "## 文件" section of each of those AGENTS.md lists exactly the directory's .go files;
  - the entry package holds only the assembly files (ENTRY_FILES) besides its tests;
  - integration tests (*_integration_test.go) are only in itest/, and itest/ holds only tests;
  - the module table of internal/AGENTS.md has one row per package under internal/, and its dependency column is
    what `go list` says the package imports from internal/;
  - the component's AGENTS.md links every package under internal/ (internal/<pkg>/AGENTS.md).

Usage: layout-check.py
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
ENTRY_FILES = {"definition.go", "module.go", "services.go", "checks.go"}


def components(root: pathlib.Path) -> list[tuple[str, pathlib.Path]]:
    out = []
    for y in sorted(root.glob("components/*/*/component.yaml")):
        d = y.parent
        text = y.read_text()
        version = re.search(r"^  version:\s*(\S+)", text, re.M)
        cid = re.search(r"^  id:\s*(\S+)", text, re.M)
        if version and cid and version.group(1).startswith("3.") and (d / "go.mod").exists() and (d / "main.go").exists():
            out.append((cid.group(1), d))
    return out


def entry_package(d: pathlib.Path) -> str | None:
    m = re.search(r"launcher\.Main\((\w+)\.Definition\(\)\)", (d / "main.go").read_text())
    return m.group(1) if m else None


def files_section(agents: pathlib.Path) -> set[str] | None:
    m = re.search(r"^## 文件\n(.*?)(?=^## |\Z)", agents.read_text(), re.S | re.M)
    if not m:
        return None
    return set(re.findall(r"^\| `([^`/]+\.go)` \|", m.group(1), re.M))


def module_table(agents: pathlib.Path) -> dict[str, set[str]]:
    """The rows `| `pkg`（…） | what | deps |` of internal/AGENTS.md's module table: package → its dependencies."""
    m = re.search(r"^## 模块\n(.*?)(?=^## |\Z)", agents.read_text(), re.S | re.M)
    rows = {}
    for line in (m.group(1) if m else "").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        name = re.match(r"`(\w+)`", cells[0]) if cells else None
        if name and len(cells) >= 3:
            rows[name.group(1)] = set(re.findall(r"`(\w+)`", cells[-1]))
    return rows


def go_imports(d: pathlib.Path) -> dict[str, set[str]]:
    """Each package under internal/ → the packages under internal/ it imports (go list)."""
    out = subprocess.run(["go", "list", "-f", "{{.ImportPath}} {{join .Imports \" \"}}", "./internal/..."], cwd=d,
                         capture_output=True, text=True, check=True).stdout
    deps = {}
    for line in out.splitlines():
        path, *imports = line.split()
        deps[path.rsplit("/", 1)[-1]] = {i.rsplit("/", 1)[-1] for i in imports if "/internal/" in i}
    return deps


def check(cid: str, d: pathlib.Path, imports=go_imports) -> list[str]:
    errs = []
    pkg = entry_package(d)
    if not pkg or not (d / pkg).is_dir():
        return [f"{cid}: main.go does not run launcher.Main(<pkg>.Definition()) of a package in the repository"]
    internal = d / "internal"
    modules = sorted(p for p in internal.iterdir() if p.is_dir() and any(p.glob("*.go"))) if internal.is_dir() else []
    if not modules:
        errs.append(f"{cid}: no business packages under internal/")
    itest = d / "itest"
    for layer in [d / pkg, internal, *modules, itest]:
        rel = layer.relative_to(d)
        agents, claude = layer / "AGENTS.md", layer / "CLAUDE.md"
        if not layer.is_dir():
            errs.append(f"{cid}: {rel}/ is missing")
            continue
        if not agents.exists():
            errs.append(f"{cid}: {rel}/AGENTS.md is missing")
        if not claude.exists() or claude.read_text().strip() != "@AGENTS.md":
            errs.append(f"{cid}: {rel}/CLAUDE.md is missing or is not exactly @AGENTS.md")
        gofiles = {f.name for f in layer.glob("*.go")}
        if agents.exists() and gofiles:
            listed = files_section(agents)
            if listed is None:
                errs.append(f"{cid}: {rel}/AGENTS.md has no \"## 文件\" section")
            else:
                for f in sorted(gofiles - listed):
                    errs.append(f"{cid}: {rel}/{f} is not in {rel}/AGENTS.md's 文件")
                for f in sorted(listed - gofiles):
                    errs.append(f"{cid}: {rel}/AGENTS.md lists {f}, which is not in {rel}/")
    for f in sorted((d / pkg).glob("*.go")):
        if not f.name.endswith("_test.go") and f.name not in ENTRY_FILES:
            errs.append(f"{cid}: {pkg}/{f.name}: the entry package only assembles ({', '.join(sorted(ENTRY_FILES))}); "
                        "business goes under internal/")
    for f in sorted(d.rglob("*_integration_test.go")):
        if f.parent != itest:
            errs.append(f"{cid}: {f.relative_to(d)}: integration tests are in itest/")
    if itest.is_dir():
        for f in sorted(itest.glob("*.go")):
            if not f.name.endswith("_test.go"):
                errs.append(f"{cid}: itest/{f.name}: itest/ holds only tests")
    if (internal / "AGENTS.md").exists() and modules:
        table = module_table(internal / "AGENTS.md")
        actual = imports(d)
        for m in modules:
            if m.name not in table:
                errs.append(f"{cid}: internal/{m.name} has no row in internal/AGENTS.md's 模块")
            elif table[m.name] != actual.get(m.name, set()):
                errs.append(f"{cid}: internal/AGENTS.md says {m.name} depends on {sorted(table[m.name])}, "
                            f"it imports {sorted(actual.get(m.name, set()))}")
        for name in sorted(set(table) - {m.name for m in modules}):
            errs.append(f"{cid}: internal/AGENTS.md's 模块 has {name}, which is not under internal/")
    root_map = (d / "AGENTS.md").read_text() if (d / "AGENTS.md").exists() else ""
    for m in modules:
        if f"internal/{m.name}/AGENTS.md" not in root_map:
            errs.append(f"{cid}: AGENTS.md does not link internal/{m.name}/AGENTS.md")
    return errs


def main(argv: list[str]) -> int:
    errs, ok = [], []
    for cid, d in components(ROOT):
        e = check(cid, d)
        errs += e
        if not e:
            ok.append(cid)
    for cid in ok:
        print(f"✅ {cid}")
    for e in errs:
        print(f"❌ {e}")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
