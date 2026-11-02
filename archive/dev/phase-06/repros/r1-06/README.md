# R1 #6：三门迁移工具是否忽略 `migrations/lifecycle.yaml`，状态表能否放进组件 schema

## 假设

来自 `sdk-redesign.md` §7.9 第 6 条和 `data-layer.md` §6 第 1 步（支撑 P11.3、P11.1，以及 data-layer §3.4 的"SDK 平台迁移"）：

1. golang-migrate（iofs）、yoyo、node-pg-migrate 都会忽略和迁移文件放在一起的 `migrations/lifecycle.yaml`；
2. 三者的状态表都能放进组件自己的 schema；
3. （data-layer §6 第 1 步顺带点名）同一个 schema 里可以放两套迁移：组件自己的 + SDK 平台迁移。

## 环境与版本

- `postgres:16-alpine`（16.15），一次性容器 `r1-r1a-pg06-<pid>`，跑完即删（含卷）。每个工具一个组件身份：角色 `c_go` / `c_py` / `c_node` / `c_node2`，各自拥有 `s_go` / `s_py` / `s_node` / `s_node2`。角色名和 schema 名故意不同，不靠 `"$user"` 碰巧命中；`public` 上没有 CREATE 权（PG15 起的默认）。
- Go：go 1.26.0，golang-migrate v4.20.1（当前最新，也是 be-sdk-go 钉的版本）+ `database/pgx/v5` 驱动 + `source/iofs`，pgx v5.10.0。连接串写法照搬 `tools/be-sdk-go/migrate/migrate.go`：`search_path=<schema>` 和 `x-migrations-table=<表名>`。
- Python：3.14.4，yoyo-migrations 9.0.0，psycopg 3.3.6（`uv run --with-requirements`，不留虚拟环境）。
- TS：Node 24.21.0，node-pg-migrate 9.0.0，pg 8.23.1（`node_modules` 不提交）。

## 步骤

`./run.sh`：起容器、建身份，然后依次跑三段程序。三个 `migrations/` 目录里都有同一份 `lifecycle.yaml`（形状同 data-layer §3.4）和两份组件迁移；`platform/` 目录是一份 SDK 平台迁移（`besdk_outbox`）。

| 工具 | 程序 | 做了什么 |
|---|---|---|
| golang-migrate | `go/main.go` | 组件迁移进 `schema_migrations_<schema>`，平台迁移进 `besdk_migrations_<schema>`；up、重复 up、down 1、再 up |
| yoyo | `py/run_yoyo.py` | URL 带 `?schema=<schema>`；平台迁移 id 带 `besdk-` 前缀，和组件迁移共用 yoyo 的状态表；apply、重复 apply、回滚 1、再 apply |
| node-pg-migrate | `node/run.mjs` | `schema` + `migrationsSchema` + `migrationsTable`；N1 用默认选项，N2 起加 `ignorePattern`；N6/N7 让两个组件（不同 schema）同时迁移 |

## 原始输出（关键几行）

```
== golang-migrate (iofs, pgx5)
INFO source.DefaultParse(lifecycle.yaml) err=no match
INFO iofs component versions=[1 2]
PASS component down 1: component=1(dirty=false) platform=1(dirty=false)
TABLE s_go.besdk_migrations_s_go
TABLE s_go.schema_migrations_s_go
== yoyo
INFO component ids= ['0001_create_widgets', '0002_add_note']
PASS rollback 1 component migration; applied ids now = ['0001_create_widgets', 'besdk-0001_outbox']
TABLE s_py._yoyo_log
TABLE s_py._yoyo_migration
TABLE s_py._yoyo_version
TABLE s_py.yoyo_lock
== node-pg-migrate
PASS N1 default options with lifecycle.yaml (expected error): Error loading migration files: Cannot determine numeric prefix for "lifecycle.yaml"
PASS N2 ignorePattern skips non-.sql: 1700000000001_create-widgets,1700000000002_add-note
PASS N3 platform migrations, second state table: 1700000000001_besdk-outbox
PASS N6 concurrent, default lock (expected error): Another migration is already running. Advisory lock mode is set to 'fail'.
PASS N7 concurrent, per-schema lockValue
TABLE s_node.besdk_migrations_s_node
TABLE s_node.pgmigrations_s_node
== tables in public (must be none)
0
```

## 结论

**部分成立。**

| | 忽略 `lifecycle.yaml` | 状态表在组件 schema | 同一 schema 两套迁移 |
|---|---|---|---|
| golang-migrate（iofs） | **成立**：文件名不匹配 `^[0-9]+_.*\.(up\|down)\..*$` 的文件直接跳过 | **成立**：`search_path` + `x-migrations-table` | **成立**：两张状态表，版本各走各的，down 组件不影响平台 |
| yoyo | **成立**：只认 `.py` / `.sql` | **成立**：`?schema=` 让全部 4 张内部表落进组件 schema | **成立**：共用状态表，靠 `besdk-` 前缀区分；回滚组件迁移不动平台迁移 |
| node-pg-migrate | **不成立**：默认读目录里除点文件以外的全部文件，`lifecycle.yaml` 让整次迁移失败 | **成立**：`schema` + `migrationsSchema` + `migrationsTable` | **成立**：第二张状态表 `besdk_migrations_<schema>` |

另有三点发现：

1. **node-pg-migrate 的默认锁是全库常量。** 锁键 `7241865325823964`，模式 `fail`（`pg_try_advisory_lock`，拿不到就报错）。同一个库里两个 TS 组件同时迁移（compose 一起启动时就是这样），后一个直接失败（N6）。锁键按 schema 派生、模式改成 `wait` 之后两者并行成功（N7）。golang-migrate 的锁键由库名 + schema + 状态表名派生，yoyo 用的是组件 schema 里的 `yoyo_lock` 表，这两个天然按组件隔离。
2. **三者都用会话级的东西**：yoyo 和 node-pg-migrate 执行会话级 `SET search_path`，golang-migrate 和 node-pg-migrate 用会话级 `pg_advisory_lock`。迁移走直连（P11.1），这没问题，但和 P10.2 "会话级 SET 一律禁止"、P10.8 "会话级锁一律禁止"字面冲突。
3. golang-migrate 的文件名规则不看扩展名：`001_x.up.md` 也会被当成 SQL 执行。`lifecycle.yaml` 不受影响，但门禁可以顺手查一下迁移目录里只有 `.sql` 和 `lifecycle.yaml`。

## 对设计的影响

1. **TS SDK 的迁移入口必须显式传 `ignorePattern`**，只认 `.sql`，正则写 `(\..*)|(.*(?<!\.sql))`（node-pg-migrate 把它当成 `^(…)$` 的整名匹配正则，本复现 N2 用的就是这一条）。写进 `sdk-redesign-apis.md` TS 的 `migrate` 一节和 foundations 08。不推荐把 `lifecycle.yaml` 挪出 `migrations/`：Go 和 Python 两边已经验证可以放在一起，三门语言保持同一个目录形状更重要。
2. **TS SDK 的迁移入口必须传 `lockValue` 和 `advisoryLockMode: 'wait'`**：`lockValue` 由 `PG_SCHEMA` + 状态表名派生（例如 FNV-1a 截到 53 位，确保 JS number 精确表示），不能用默认常量。可以作为 compconf 的一个用例："两个组件同库并发迁移都成功"。
3. **P11.1 补一句例外**："迁移连接是直连的专用会话，工具自身的会话级 `search_path` 和会话级 advisory 锁在这里允许；P10.2、P10.8 的禁令只针对运行期的池化连接。"
4. **P11.3 的"表名由各语言的工具决定"写成具体的表**：Go `schema_migrations_<PG_SCHEMA>` + `besdk_migrations_<PG_SCHEMA>`；Python `_yoyo_migration`、`_yoyo_log`、`_yoyo_version`、`yoyo_lock`（平台迁移 id 带 `besdk-` 前缀，共用这几张）；TS `pgmigrations_<PG_SCHEMA>` + `besdk_migrations_<PG_SCHEMA>`。生命周期引擎和门禁若要检查"schema 里每张表都在 `lifecycle.yaml` 里有声明"（P11.11），要把这些工具表列为白名单。
