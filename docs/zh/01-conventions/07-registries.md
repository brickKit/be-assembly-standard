[English](registries.md) · [中文](registries.zh.md)

# 登记表

`registry/` 放着项目级的几张表，写 `component.yaml` 或 `assembly.yaml` 之前从这里抄。端口、schema、角色、权限键从来不自己编：要么从这里来，要么先在这里追加一行。

## 四张表

| 文件 | 内容 | 规则 |
|---|---|---|
| `registry/ports.tsv` | 每个组件的 HTTP 和 gRPC 端口、每个外壳自己的端口、每个带外容器的宿主机端口 | 只追加 |
| `registry/schemas.tsv` | 每个组件的 PostgreSQL schema 和角色 | 只追加 |
| `registry/permissions.tsv` | 每个权限键：`key`、`title`、`type`、`owner_component`、`deprecated` | 只追加；由 be-ops 汇总 |
| `registry/data-scopes.tsv` | 每个数据范围维度：`component`、`dimension`、`column`、`mode`、`tables` | 纯派生；随时可重新生成 |

"组件 → 仓库"的对照是 `.gitmodules`：每个组件是 `components/<scope>/<name>/` 下的一个 Git submodule，本仓库记录着每个组件的确切提交。

## 只追加

`ports.tsv`、`schemas.tsv`、`permissions.tsv` 只会新增行。

- **一旦有了依赖方，端口就不能挪。** 每个依赖方都按组件声明的端口访问它；同一个外壳的成员共享一个网络命名空间，两个成员用同一个端口会在一个进程里撞车。改一个端口，就是改所有依赖方和所有可能承载它的外壳。
- **数据进去之后，schema 就不能改名**：那是一次数据迁移。
- **已发布的权限键不能改名。** 所有被授予旧键的角色会静默失去它，不报任何错；症状是客户一升级，某些用户突然点不了某个按钮。键要退役就填它的 `deprecated` 列，键名永不回收。
- 改完之后跑 `make registry-check`。

## 端口

**分配规则**：端口一律从 `ports.tsv` 抄，不自己推算。端口按组分配；组内第 n 个组件的 HTTP 是该组 HTTP 基址 + n，gRPC 是该组 gRPC 基址 + n，基址见下表（8080 ↔ 9090、8100 ↔ 9100、8200 ↔ 9200、8300 ↔ 9300、8400 ↔ 9400）。`ports.tsv` 的 `shell` 列写的就是组名。

| 组 | HTTP | gRPC |
|---|---|---|
| Go 核心交易与主数据 | 8080–8087 | 9090–9097 |
| Go 后台 | 8100–8115 | 9100–9115 |
| Go 基础设施与集成 | 8200–8223 | 9200–9223 |
| Python 领域引擎 | 8300–8307 | 9300–9307 |
| Python 渲染与 EDI | 8400–8401 | 9400–9401 |
| 独立容器（BFF） | 8500 | — |
| 前端 | 80 | — |

- 以 `_shell-` 开头的行是外壳自己的端口（它的健康检查），不是任何成员的端口。
- 以 `_infra-` 开头的行是带外容器（PostgreSQL、NATS、Traefik、Casdoor、对象存储、可观测性），不是组件。它们和组件处在同一个宿主机端口空间里，所以也要登记。
- **共用端口的唯一例外**：前端槽位族共用 80（同时只会装一个）；互斥的带外容器两两共用端口（RustFS / MinIO 都是 9000，Traefik / Nginx 都是 80）。`make registry-check` 只放行这两类。
- 每个端口在所有组件之间唯一，包括永不同时运行的槽位成员和还没开发的蓝图：预留一行不花成本，晚发现的冲突要所有依赖方买单。
- **`1xxxx` 整段归 brickKit。** 对 `mode: debug` 和 `mode: local`，brickKit 把容器端口映射到宿主机的 `10000 + 端口`（5432 → 15432，8080 → 18080），被占时从 `18080` 起递增。绝不分配 `1xxxx` 端口。带外容器的默认端口不和任何东西撞时保持不变（PostgreSQL 5432、NATS 4222、Casdoor 8000）；会撞组件端口或 `1xxxx` 段的默认端口或 `exposePort` 宿主机端口，挪到 `2xxxx` 段（Traefik 面板 28080、Keycloak 28081、Prometheus 29090、Kafka 29092、前端 28090、BFF 28500）。它们都登记在 `ports.tsv` 里。

## schema 与角色

| 对象 | 规则 | 例子 |
|---|---|---|
| 数据库 | 运行中的项目用 `brickkit_db`，测试用 `brickkit_test_db` | — |
| 组件 schema | 仓库名的 `-` 换成 `_` | `mdm-customer` → `mdm_customer` |
| 归档 schema | `<schema>_archive` | `mdm_customer_archive` |
| 组件角色 | `<schema>_rw`，登录角色，密码 `${<REPO>_DB_PASSWORD}` | `mdm_customer_rw`、`${MDM_CUSTOMER_DB_PASSWORD}` |
| 外壳登录角色 | `shell_<name>`，是它承载的每个组件角色的成员 | `shell_go_core` |

- brickKit 从不建数据库、schema 或角色。`make db-init` 执行 be-ops 根据这些表和外壳成员清单生成的脚本（`CREATE SCHEMA`、角色、授权），幂等可重跑。`make test-db-init` 对测试库做同样的事。
- 角色和密码怎么交到组件手上：见 [configuration.zh.md](configuration.zh.md#数据库角色)。
- 外壳的每个成员在 `schemas.tsv` 里都有一行；成员没有行的外壳，be-ops 拒绝生成。
- 不建 schema 的：`infra/bff-mobile`（从不直连数据库）、前端、不开发的蓝图。非组件 schema：`casdoor`（Casdoor 镜像自用）、`keycloak`（换用那个槽位成员时）。

## 权限键

- 键是 `<domain>.<aggregate>.<action>`；前缀等于所属组件的领域，全项目唯一。在代码里怎么声明和注册：见 [backend.zh.md](backend.zh.md#权限)。
- `be-ops permissions --root .` 读每个组件的 `assembly.yaml`，把新键合并进 `permissions.tsv`。它只增不删：没有组件再声明、又没标 `deprecated` 的键会打警告并留在表里；退役靠人在 `deprecated` 列手工打墓碑。
- 加了新键之后，刷新 infra/authz 配置里的权限目录。不在那里的键永远进不了权限列表，对它的每次校验都失败。
- `data-scopes.tsv` 由 `data_scopes` 段用同样的方式产出。它存在的意义是：客户安全审查或交付验收只读一张表，不用一个个组件去翻。
