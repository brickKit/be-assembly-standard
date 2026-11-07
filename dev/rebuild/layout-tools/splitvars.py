#!/usr/bin/env python3
"""Split every top-level `var ( ... )` block whose members are named in argv[2:] into one `var` declaration per member,
so a mover can take them apart. Usage: splitvars.py <file.go> NAME [NAME ...]"""
import pathlib, re, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text(); names = set(sys.argv[2:])
out, i = [], 0
for m in re.finditer(r"^var \(\n(.*?)^\)\n", s, re.S | re.M):
    body = m.group(1)
    starts = [(x.start(), x.group(1)) for x in re.finditer(r"^\t(\w+)\s+=", body, re.M)]
    if not names & {n for _, n in starts}:
        continue
    pieces = []
    for k, (a, n) in enumerate(starts):
        b = starts[k + 1][0] if k + 1 < len(starts) else len(body)
        piece = body[a:b].rstrip("\n")
        # leading comment lines of the next member belong to it: they sit before its start, inside this piece
        lines = piece.split("\n")
        piece = "\n".join(l[1:] if l.startswith("\t") else l for l in lines)
        piece = re.sub(r"^(\w+)\s+=", r"var \1 =", piece, count=1)
        pieces.append(piece)
    out.append((m.start(), m.end(), "\n\n".join(pieces) + "\n"))
for a, b, text in reversed(out):
    s = s[:a] + text + s[b:]
p.write_text(s)
