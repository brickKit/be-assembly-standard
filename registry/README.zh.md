[English](README.md) · [中文](README.zh.md)

# 登记表

组件写 `component.yaml` 或 `assembly.yaml` 之前要照抄的全项目表。端口、schema、角色、权限键从不自拟：要么从这里抄，要么先在这里追加一行。完整规则见[协议 19 的注册表](../docs/zh/06-protocols/19-config-secrets-registries-release.md#注册表)；本页只说明每个文件是什么。

## 文件

| 文件 | 内容 | 规则 |
|---|---|---|
| `ports.tsv` | 每个组件的 HTTP 和 gRPC 端口、每个外壳自己的端口、每个带外容器的宿主机端口 | 只增不改 |
| `schemas.tsv` | 每个组件的 PostgreSQL schema 与运行角色（`role` 列）；属主角色固定为 `<schema>_owner`，不单列（协议 14：属主角色只供迁移，运行角色只有业务所需权限） | 只增不改 |
| `permissions.tsv` | 每个权限键：`key`、`title`、`type`、`owner_component`、`deprecated` | 只增不改；由 `be-ops permissions` 合并进来 |
| `data-scopes.tsv` | 每个数据范围维度：`component`、`dimension`、`column`、`mode`、`tables` | 派生表，可随时重新生成 |

## 规则

- **只增不改**（`ports.tsv`、`schemas.tsv`、`permissions.tsv`）：端口一挪，每个依赖方和每个托管这个组件的外壳都会坏；schema 一改名就是一次数据迁移；权限键一改名，所有分配过它的角色都会静默失去它。键的废弃靠填 `deprecated`，键名永不复用。
- **退役**：组件不再使用时，`ports.tsv` 的备注列写 `retired <日期>：<原因>`，行保留；它的名字、端口与 schema 不再分配（例：`mdm/customer` 改名为 `mdm/partner`，D20）。
- **`_infra-` 开头的行**是带外容器（PostgreSQL、NATS、Traefik、Casdoor、对象存储、可观测性），不是组件。它们和组件共用宿主机端口空间，所以也登记；互斥的一对（RustFS / MinIO、Traefik / Nginx）可以共用一个端口。
- **`_shell-` 开头的行**是外壳自己的端口，即各外壳 `component.yaml` 里 `/healthz` 的端口（`deployment.port`）。外壳 ID 是 `be/<name>`。被外壳托管的成员保留自己的服务名和自己的端口。
- 端口按组分配，组见 `ports.tsv` 里的分节注释；`1xxxx` 段留给 BrickKit 给本机进程做的映射（10000 + 容器端口），带外容器的宿主机端口用 `2xxxx` 段。外壳列是部署时的分配，实验之后按 D40 再定。
- 改完任何一处都跑 `make registry-check`（`infra/scripts/registry_check.py`：端口两两不重复、80 端口的归属、schema 与运行角色的命名、两表对应、外壳列与登录角色对应）。
