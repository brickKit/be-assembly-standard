# be-assembly-standard

BrickEnterprise：ERP 为主、加入 CRM 的组件货架，以及用 [BrickKit](https://github.com/brickKit/brickKit) 把它们装配起来的标准项目；每个组件可以单独运行，也可以合进外壳，跑在 Docker、Podman 或 Kubernetes 上。

终局设计已于 2026-10-15 冻结，正式文档在 [docs/zh/](docs/zh/README.md)。现有的组件（2.x）是旧设计的实现，按新设计从零重建（D59）；重建期间，下面的快速开始仍然启动这套旧组件。

## 快速开始

前提：Docker、`brickkit` 命令行、`make`、`curl`、`python3`。带子模块克隆（`git clone --recurse-submodules`，或之后 `git submodule update --init`）。

```bash
make up            # 基础资源：PostgreSQL、NATS、Casdoor、Traefik、RustFS
make dev-env       # 给每个数据库角色写一个随机密码到 .env（只补缺的）
make db-init       # 建 schema、角色与授权（可重复执行）
brickkit build     # 构建项目中组件的镜像
brickkit up        # 启动 brickkit.yaml 列出的全部组件
make seed-data     # 演示数据与测试账号
brickkit down      # 用完停掉组件容器（数据保留）
```

`make help` 列出全部目标；`make check` 说明缺了哪个基础资源或配置不对；`make gates` 运行文档检查与装配预检。

## 文档

| 问题 | 读什么 |
| --- | --- |
| 我是 AI（或要给 AI 交代）：这个项目是什么、规则是什么、去哪里找 | [AGENTS.md](AGENTS.md) |
| 产品、领域与边界、组件全景、客户组合 | [docs/zh/00-overview/](docs/zh/00-overview/README.md) |
| 每个组件都遵守的规则：开发流程、组件实现、测试、数据、文档 | [docs/zh/01-conventions/](docs/zh/01-conventions/README.md) |
| 项目为什么是这个样子；哪些方向已经排除 | [docs/zh/02-decisions/](docs/zh/02-decisions/README.md) |
| 跨组件的协议：授权、事务、出账、关账、恢复…… | [docs/zh/06-protocols/](docs/zh/06-protocols/README.md) |
| 部署：要准备什么、建哪些库与角色、哪些密钥 | 各组件 `BRICKKIT.md` 的“部署前准备”；`.claude/skills/` 中的 `brickkit-deploy` 技能；[运维手册](docs/zh/05-operations/README.md) |
| 某个组件做什么、怎样改它 | [AGENTS.md](AGENTS.md) 末尾的组件表，然后 `components/<scope>/<name>/` 中的 `BRICKKIT.md` 与 `AGENTS.md` |
| BrickKit 本身：命令、参数、错误码 | `brickkit <命令> --help`；`.claude/skills/brickkit-*` 中的技能 |

## 仓库布局

```
brickkit.yaml                组件与它们的精确版本（锁文件）
deploy.yaml                  怎样运行：目标、外壳、对外端口
config/                      每个组件的配置值；vars.yaml 放多个组件共用的值
components/<scope>/<name>/   每个组件一个 Git 子模块
shell/<scope>/<name>/        每个外壳一个 Git 子模块：几个组件在一个进程里
tools/                       be-sdk-go、be-sdk-python、be-sdk-ts、be-ops、be-acceptance
registry/                    端口、schema、权限键等注册表
infra/                       make up 启动的基础资源与项目脚本
docs/zh/                     正式文档（开发完成前只写中文）
dev/                         进行中的工作（重建计划等）
archive/                     归档：旧文档与设计过程；现行内容不引用
```
