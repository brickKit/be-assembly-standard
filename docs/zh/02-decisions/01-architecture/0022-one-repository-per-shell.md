[English](0022-one-repository-per-shell.md) · [中文](0022-one-repository-per-shell.zh.md)

# 0022 一个外壳、一个仓库、一个镜像、一份成员清单

## 决策

每个外壳和组件一样是独立的 Git 仓库：`be/go-core`、`be/go-infra`、`be/go-backoffice`、`be/py-render` 分别在 `brickKit/be-go-core`、`be-go-infra`、`be-go-backoffice`、`be-py-render`，本项目把它们以 Git 子模块的形式检出在 `shell/<scope>/<name>/`，`brickkit.yaml` 里的 `local-shells` 安装源从那里找到它们。外壳在它自己仓库的根目录用 `brickkit release --notes-file` 发布；tag 是裸版本号（`1.0.0`），不打 `v` tag，因为没有人把外壳当 Go 模块或 Python 包 import。一个外壳对应一个镜像和一份成员清单：`component.yaml` 里的 `shell.members` 列出编译进去的成员的精确版本，外壳代码注册的成员与之完全一致——不多也不少。加成员或把成员换到新版本，就是在外壳仓库里提交并发布，再回到本仓库提交子模块指针、跑 `brickkit upgrade be/<name>@<版本>`。一次部署实际托管编译进来的哪些成员，在部署文件中选择（外壳条目下的 `members:`）。外壳只负责把 N 个进程变成 1 个：启动器逻辑在 SDK 里，每个成员的迁移仍从成员自己的镜像运行，一个外壳从不混用语言。

## 理由

外壳会被别的装配项目（客户项目、干净的入门项目）复用，它们都需要用同一份成员清单构建出同一个镜像，所以外壳不能是某一个项目里的代码。作为独立仓库，它的发布、版本钉和升级都和组件完全一样，子模块指针记下本项目构建的是哪个提交。成员清单是对镜像内容的承诺：没有编译进去的成员版本无法被托管，`brickkit up` 会检查镜像上的成员标签。启动器放在 SDK 里，每个外壳就只剩一份成员清单，不会长出自己的逻辑。

## 挡下什么

- 把外壳代码直接提交在本仓库，而不是外壳自己的仓库；把启动器代码复制进每个外壳
- 在本仓库用 `brickkit release --path` 发布外壳、在这里打 `be-<name>/<版本>` tag，或给外壳打 `v` tag
- 在外壳代码里写业务逻辑、路由、数据访问或成员之间的调用
- 因为在同一个外壳里，成员之间就在进程内直接调用（[0001](0001-no-imports-between-components.zh.md)）
- "只升级 `erp/sales`，外壳不动"——成员换了新版本，外壳就要升版本、发布、重新构建
- 外壳注册的成员与它的 `shell.members` 不一致
- 在一个外壳里混放 Go 和 Python 成员；把 TypeScript BFF 或前端放进外壳
- 由外壳来运行成员的迁移

`brickkit up --ignore-shells` 让每个成员各自独立运行，本项目用它来检查每个组件是否仍能单独启动。

## 何时重新讨论

从来没有别的项目复用外壳时；届时外壳可以搬回本仓库，作为项目代码。
