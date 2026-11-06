TITLE = "suite 1.0.57: the cells' configuration from what members declare (run profile, object store, unset keys)"
BUILD = ["uv", "run", "python", "-c", "import cells.prepare"]
TEST = ["uv", "run", "pytest", "-q", "tests/test_cell_config.py"]
ENV = {"PYTHONDONTWRITEBYTECODE": "1"}
F = "cells/prepare.py"
MUTANTS = [
    (F, '            if key in conf or key in UNSET_ON_PURPOSE or "default" in prop', '            if True or key in conf or key in UNSET_ON_PURPOSE or "default" in prop', "an unset key is named"),
    (F, ' or "default" in (prop.get("description") or "").lower():', ':', "a key whose description names a default is not"),
    (F, '            if key in conf or key in UNSET_ON_PURPOSE', '            if key in conf', "a key unset on purpose is not"),
    (F, '            if declares(c, comp, "OBJECT_STORE_URL"):', '            if declares(c, comp, "OBJECT_STORE_URL") and False:', "a producer gets the object store"),
    (F, '                         f"OBJECT_STORE_PREFIX: {schema_of(comp)}/",', '                         "OBJECT_STORE_PREFIX: x/",', "its own prefix"),
]
