[English](README.md) · [中文](README.zh.md)

# 登记表

组件写 `component.yaml` 或 `assembly.yaml` 之前要照抄的全项目表。端口、schema、角色、权限键从不自拟：要么从这里抄，要么先在这里追加一行。完整规则见 [docs/zh/01-conventions/07-registries.md](../docs/zh/01-conventions/07-registries.md)；本页只说明每个文件是什么。

## 文件

| 文件 | 内容 | 规则 |
|---|---|---|
| `ports.tsv` | 每个组件的 HTTP 和 gRPC 端口、每个外壳自己的端口、每个带外容器的宿主机端口 | 只增不改 |
| `schemas.tsv` | 每个组件的 PostgreSQL schema 和登录角色 | 只增不改 |
| `permissions.tsv` | 每个权限键：`key`、`title`、`type`、`owner_component`、`deprecated` | 只增不改；由 `be-ops permissions` 合并进来 |
| `data-scopes.tsv` | 每个数据范围维度：`component`、`dimension`、`column`、`mode`、`tables` | 派生表，可随时重新生成 |

## 规则

- **只增不改**（`ports.tsv`、`schemas.tsv`、`permissions.tsv`）：端口一挪，每个依赖方和每个托管这个组件的外壳都会坏；schema 一改名就是一次数据迁移；权限键一改名，所有分配过它的角色都会静默失去它。键的废弃靠填 `deprecated`，键名永不复用。
- **`_infra-` 开头的行**是带外容器（PostgreSQL、NATS、Traefik、Casdoor、对象存储、可观测性），不是组件。它们和组件共用宿主机端口空间，所以也登记；互斥的一对（RustFS / MinIO、Traefik / Nginx）可以共用一个端口。
- **`_shell-` 开头的行**是外壳自己的端口，即各外壳 `component.yaml` 里 `/healthz` 的端口（`deployment.port`）。外壳 ID 是 `be/<name>`。被外壳托管的成员保留自己的服务名和自己的端口。
- 端口分组、brickKit 保留的 `1xxxx` 段、带外宿主机端口用的 `2xxxx` 段：见 [07-registries.md](../docs/zh/01-conventions/07-registries.md#端口)。
- 改完任何一处都跑 `make registry-check`。
