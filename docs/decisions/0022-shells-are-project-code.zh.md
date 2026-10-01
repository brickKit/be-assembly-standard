[English](0022-shells-are-project-code.md) · [中文](0022-shells-are-project-code.zh.md)

# 0022 外壳是项目代码：一个外壳、一个镜像、一份成员清单

## 决策

外壳是本项目的代码，不是独立仓库：放在 `shell/<scope>/<name>/` 下，用 `brickkit new --shell` 生成。外壳有 `be/go-core`、`be/go-infra`、`be/go-backoffice` 和 `be/py-render` 四个，发布 tag 的格式为 `<scope>-<name>/<version>`。一个外壳对应一个镜像和一份成员清单：`component.yaml` 里的 `shell.members` 列出编译进去的成员的精确版本，外壳代码注册的成员与之完全一致——不多也不少。一次部署实际托管哪些成员，在部署文件中选择（外壳条目下的 `members:`）。外壳只负责把 N 个进程变成 1 个：启动器逻辑在 SDK 里，每个成员的迁移仍从成员自己的镜像运行，一个外壳从不混用语言。

## 理由

哪些组件共享一个进程，是本项目的部署选择，所以外壳放在 `brickkit.yaml` 和 `deploy.yaml` 旁边，与它们在同一个提交里一起变。成员清单是对镜像内容的承诺：没有编译进去的成员版本无法被托管，`brickkit up` 会检查镜像上的成员标签。启动器放在 SDK 里，每个外壳就只剩一份成员清单，不会长出自己的逻辑。

## 挡下什么

- 每个外壳一个独立的 Git 仓库，或把启动器代码复制进每个外壳
- 在外壳代码里写业务逻辑、路由、数据访问或成员之间的调用
- 因为在同一个外壳里，成员之间就在进程内直接调用（[0001](0001-no-imports-between-components.zh.md)）
- "只升级 `erp/sales`，外壳不动"——成员换了新版本，外壳就要升版本、重新构建、重新发布
- 外壳注册的成员与它的 `shell.members` 不一致
- 在一个外壳里混放 Go 和 Python 成员；把 TypeScript BFF 或前端放进外壳
- 由外壳来运行成员的迁移

`brickkit up --ignore-shells` 让每个成员各自独立运行，本项目用它来检查每个组件是否仍能单独启动。

## 何时重新讨论

同一批外壳需要被多个项目共用时；届时它们会迁到各自的仓库。
