"""Each code directory has AGENTS.md and CLAUDE.md, and the backticked file names in AGENTS.md's "## 文件" section
are exactly the directory's .go files (a prototype of layout-plan.md A163)."""
import pathlib, re, sys
root = pathlib.Path(sys.argv[1]); bad = 0
for d in [root / "sales", root / "itest"] + sorted((root / "internal").iterdir()):
    if not d.is_dir():
        continue
    a, c = d / "AGENTS.md", d / "CLAUDE.md"
    if not a.exists() or not c.exists() or c.read_text().strip() != "@AGENTS.md":
        print("MISSING docs:", d); bad += 1; continue
    go = {f.name for f in d.glob("*.go")}
    if not go:
        continue
    sec = re.search(r"^## 文件\n(.*?)(?=^## )", a.read_text(), re.S | re.M)
    rows = re.findall(r"^\| `([^`]+\.go)` \|", sec.group(1) if sec else "", re.M)
    listed = set(rows)
    if listed != go:
        print(d, "missing:", sorted(go - listed), "extra:", sorted(listed - go)); bad += 1
print("BAD" if bad else "FILEMAP-OK")
sys.exit(1 if bad else 0)
