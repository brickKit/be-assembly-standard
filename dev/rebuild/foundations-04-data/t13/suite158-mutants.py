TITLE = "suite 1.0.58: a secured cell's certificates come from its issuer (be-ops trust, A148)"
BUILD = ["python3", "-c", "import ast,sys; ast.parse(open('conformance/cells/prepare.py').read())"]
TEST = ["bash", "-c", "cd conformance && uv run pytest -q -p no:cacheprovider tests/test_cell_config.py"]
ENV = {"PYTHONDONTWRITEBYTECODE": "1"}
MUTANTS = [
    ("conformance/cells/prepare.py", "    if c.secured:\n        issuer(c, \"init\")", "    if False:\n        issuer(c, \"init\")", "a secured cell uses the issuer"),
    ("conformance/cells/prepare.py", "    for d in (tls, sec / \"trust\"):", "    for d in (tls,):", "a new CA per preparation"),
    ("conformance/cells/prepare.py", "            issuer(c, \"issue\", \"--component\", comp, \"--name\", file_of(comp), \"--out\", str(tls))",
     "            issuer(c, \"issue\", \"--component\", comp, \"--name\", file_of(comp))", "the credentials go where the cell mounts them"),
    ("conformance/cells/prepare.py", "    names = [*c.placed, \"ops/recover\"]", "    names = [*c.placed]", "be-ops recover gets its credential"),
]
