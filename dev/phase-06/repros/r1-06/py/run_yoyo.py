"""R1 #6（Python 部分）：yoyo-migrations + psycopg 3。

验证：1) read_migrations 忽略 migrations/lifecycle.yaml；
2) ?schema=<PG_SCHEMA> 让 yoyo 的全部内部表（_yoyo_migration/_yoyo_log/_yoyo_version/yoyo_lock）
   落在组件 schema；3) SDK 平台迁移（id 带 besdk- 前缀）与组件迁移共用一套状态表、互不干扰。
"""
import os
import sys
from pathlib import Path

import psycopg
from yoyo import get_backend, read_migrations

here = Path(__file__).parent
dsn, schema = os.environ["DSN"], os.environ["PG_SCHEMA"]  # DSN: postgresql://u:p@h:port/db


def fail(msg):
    print(f"FAIL {msg}")
    sys.exit(1)


uri = dsn.replace("postgresql://", "postgresql+psycopg://", 1) + f"?schema={schema}"
backend = get_backend(uri)

comp = read_migrations(str(here / "migrations"))
plat = read_migrations(str(here / "platform"))
print("INFO component ids=", [m.id for m in comp])
print("INFO platform ids=", [m.id for m in plat])
if any("lifecycle" in m.id for m in comp):
    fail("lifecycle.yaml was read as a migration")

with backend.lock():
    backend.apply_migrations(backend.to_apply(comp))
print("PASS component apply")
with backend.lock():
    backend.apply_migrations(backend.to_apply(plat))
print("PASS platform apply")

left = list(backend.to_apply(comp))
if left:
    fail(f"left={left}")
print("PASS component apply again: nothing to do")

# 回滚组件最后一个迁移，平台迁移不受影响
with backend.lock():
    last = [m for m in backend.to_rollback(comp)][:1]
    backend.rollback_migrations(last)
with psycopg.connect(dsn) as c:
    ids = [r[0] for r in c.execute(
        f"SELECT migration_id FROM {schema}._yoyo_migration ORDER BY 1").fetchall()]
print("PASS rollback 1 component migration; applied ids now =", ids)
if "besdk-0001_outbox" not in ids:
    fail("platform migration disappeared after component rollback")
with backend.lock():
    backend.apply_migrations(backend.to_apply(comp))
print("PASS component re-apply")

with psycopg.connect(dsn) as c:
    for (t,) in c.execute(
        "SELECT table_schema||'.'||table_name FROM information_schema.tables "
        "WHERE table_schema NOT IN ('pg_catalog','information_schema') ORDER BY 1"
    ):
        print("TABLE", t)
