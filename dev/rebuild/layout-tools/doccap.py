"""Capitalize a doc comment's first word when the declaration it documents was exported (same name, first letter up)."""
import pathlib, re, sys
n = 0
for f in sys.argv[1:]:
    p = pathlib.Path(f); lines = p.read_text().split("\n")
    for i, l in enumerate(lines):
        m = re.match(r"^(?:func (?:\([^)]*\) )?|type )([A-Z]\w*)", l)
        if not m:
            continue
        j = i - 1
        while j >= 0 and lines[j].startswith("//"):
            j -= 1
        j += 1
        if j < i:
            w = re.match(r"^// ([a-z]\w*)\b", lines[j])
            if w and w.group(1)[0].upper() + w.group(1)[1:] == m.group(1):
                lines[j] = "// " + m.group(1) + lines[j][3 + len(w.group(1)):]
                n += 1
    p.write_text("\n".join(lines))
print("fixed", n)
