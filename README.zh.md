[English](README.md) · [中文](README.zh.md)

# be-assembly-standard

BrickEnterprise：一套 ERP/CRM 组件库，以及用 [brickKit](https://github.com/brickKit/brickKit) 把它们装配起来的标准项目；每个组件既能单独运行，也能合进外壳，跑在 Docker 或 Kubernetes 上。

## 快速开始

前提：Docker、`brickkit` 命令行、`make`、`curl`、`python3`。连同子模块一起克隆（`git clone --recurse-submodules`，或克隆后 `git submodule update --init`）。

```bash
make up            # 基础资源：PostgreSQL、NATS、Casdoor、Traefik、RustFS
make dev-env       # 给每个数据库角色生成随机密码写进 .env（只补缺的）
make db-init       # 建 schema、角色和授权（幂等）
brickkit build     # 构建本项目各组件的镜像
brickkit up        # 启动 brickkit.yaml 里列出的全部组件
make seed-data     # 演示数据和测试账号（用 dev.superuser / DevSeed123! 登录）
brickkit down      # 用完停掉组件容器（数据保留）
```

`make help` 列出所有目标；`make check` 指出哪个基础资源缺失或配置不对。演示数据和其他测试账号见 [docs/seed-data.zh.md](docs/seed-data.zh.md)。

## 文档

| 问题 | 去读 |
|---|---|
| 我是 AI（或要给 AI 交代任务）：这个项目是什么、规则是什么、去哪里找 | [AGENTS.zh.md](AGENTS.zh.md)（英文原文 [AGENTS.md](AGENTS.md)） |
| 每个组件都遵守的规则：配置、流程、后端、前端、测试、数据、登记表 | [docs/conventions/](docs/conventions/README.zh.md) |
| 项目为什么是这个形状；哪些做法已经排除 | [docs/decisions/](docs/decisions/README.zh.md) |
| 有哪些演示数据；怎么登录 | [docs/seed-data.zh.md](docs/seed-data.zh.md) |
| 部署：要准备什么、建哪些库和角色、哪些密钥 | 各组件 `BRICKKIT.md` 的 "Before you deploy" 一节；`.claude/skills/` 里的 `brickkit-deploy` 技能 |
| 某个组件是做什么的、怎么改它 | [AGENTS.md](AGENTS.md) 末尾的组件表；再看 `components/<scope>/<name>/BRICKKIT.md` 和它的 `AGENTS.md` |
| brickKit 本身：命令、参数、错误码 | `brickkit <命令> --help`；`.claude/skills/brickkit-*` 里的技能 |

## 仓库结构

```
brickkit.yaml           组件及其精确版本（锁文件）
deploy.yaml             怎么运行：目标平台、外壳、对外端口
config/                 各组件的配置值；多个组件共用的值在 vars.yaml
components/<scope>/<name>/   每个组件一个 Git 子模块
shell/<scope>/<name>/   外壳：多个组件放进一个进程，属于项目代码
tools/                  be-sdk-go、be-sdk-python、be-sdk-ts、be-ops、be-acceptance
registry/               端口、schema、权限键、数据范围
infra/                  make up 启动的基础资源，以及项目脚本
docs/                   约定、决策、种子数据
```
