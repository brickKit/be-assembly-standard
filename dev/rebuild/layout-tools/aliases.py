#!/usr/bin/env python3
"""Add the aliased imports goimports cannot guess: for each Go file given, an alias used (alias.) but not imported
gets its import line. Usage: aliases.py alias=path [alias=path ...] -- file.go ..."""
import pathlib, re, sys
args = sys.argv[1:]
i = args.index("--")
aliases = dict(a.split("=", 1) for a in args[:i])
for f in args[i + 1:]:
    p = pathlib.Path(f); s = p.read_text()
    need = [a for a in aliases if re.search(r"\b" + a + r"\.", s) and not re.search(r'^\s*' + a + r' "', s, re.M)
            and not re.search(r'^\s*"' + re.escape(aliases[a]) + '"', s, re.M)]
    if not need:
        continue
    lines = "".join(f'\t{a} "{aliases[a]}"\n' for a in need)
    if re.search(r"^import \($", s, re.M):
        s = re.sub(r"^import \($", "import (\n" + lines.rstrip("\n"), s, count=1, flags=re.M)
    else:
        s = re.sub(r"^(package \w+\n)", r"\1\nimport (\n" + lines + ")\n", s, count=1, flags=re.M)
    p.write_text(s)
