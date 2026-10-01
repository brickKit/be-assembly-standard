[English](development-workflow.md) · [中文](development-workflow.zh.md)

# 开发流程

本项目里一次改动怎样从想法走到发布的版本。代码由 AI 写、人来审，所以每一步都切到一次会话放得下的大小，人只审不可逆的东西（见 [ai-development.zh.md](ai-development.zh.md#人要审什么)；一次会话做多少见 [ai-development.zh.md](ai-development.zh.md#一次会话做多少)）。

## 七步循环

每个组件、组件里的每个功能，都走同样的七步：

```
① 设计业务逻辑        docs/design.md：边界、数据、契约、事件、依赖
② 查参考实现          先自己设计，卡住的地方才看参考
③ 写契约              contracts/*.proto、*.openapi.yaml、events/*.json
④ 写业务规则测试      不变式、状态转移、幂等（L2），写在实现之前
⑤ 实现                红 → 绿 → 重构，每轮一条规则，每轮一次提交
⑥ 补单元测试          错误路径、空值、并发（L3），写在实现之后
⑦ 集成                真实 PostgreSQL / NATS / gRPC，全部门禁，文档
```

**③ 在 ④ 之前、④ 在 ⑤ 之前，顺序不能反。** 测试要用契约生成的类型；没有契约就只能测 `map[string]any`，第一次重构就作废。实现之后才写的测试只能描述已有的代码：能防回归，防不住"从一开始就理解错了需求"。

第 ① 步见 [documentation.zh.md](documentation.zh.md#组件文档)，第 ② 步见 [reference-implementations.zh.md](reference-implementations.zh.md)，第 ④–⑥ 步见 [testing.zh.md](testing.zh.md)。

**文档先于代码。** 边界、契约、事件变了，先写进组件的 `docs/design.md`；配置或依赖变了，写进 `BRICKKIT.md`；新的禁令写进 `AGENTS.md`。文档与代码在同一个提交里改。

## 提交

- 一轮红绿一次提交。提交信息写这一轮锁定了哪条业务结论，不写改了哪些文件。
- 改测试的提交单独一个，并写清原断言错在哪里（[testing.zh.md](testing.zh.md#红绿节奏与铁律)）。
- 提交信息用中文，先写进文件，再 `git commit -F <文件>`。打 tag 之前先看 `git log --oneline -1`：命令行里引号没配对的提交信息可能静默失败，tag 就会打在上一个提交上。
- tag 一律用带注释的 tag（`git tag -a`）；`git push --follow-tags` 会一声不响地跳过轻量 tag。

## 写代码之前

每次动笔之前回答这几问：

0. **我是不是在为了让测试通过而改测试？** 默认改的是实现。测试真错了，先停下来说清错在哪里。
1. **端口和 schema 是从 `registry/` 抄的吗？** 自己编的一律是错的（[registries.zh.md](registries.zh.md)）。
2. **我是不是让两个组件互相认识对方的代码？** 调用只走 gRPC 或 HTTP 加 `contracts/`；唯一共享的代码是 `be-sdk-*` 和组件生成的契约包（[backend.zh.md](backend.zh.md#调用其他组件)）。
3. **同一个进程里再放二十个模块，这段代码还成立吗？** 不读 `os.Getenv`、不做进程级初始化、不 `log.Fatal`（[backend.zh.md](backend.zh.md#合并安全)）。
4. **我是先自己设计、再去看参考的吗？**（[reference-implementations.zh.md](reference-implementations.zh.md#三步法)）
5. **我是不是用一个 `if` 把几类客户的变体塞进了一个组件？** 几个分支各自对应一类合理但不同的客户，该做成客户 Fork（没有任何组件依赖的位置上才是槽位族），而不是一个开关（[reference-implementations.zh.md](reference-implementations.zh.md#槽位族信号)）。
6. **这个文件是不是已经太长？** 函数过 150 行、文件过 600 行、分支过 5 个还在加：见 [ai-development.zh.md](ai-development.zh.md#何时用设计模式)。
7. **这次改动牵涉哪几份文档？** 先改它们。

## 真机运行

- **先构建。** `brickkit up` 从不构建镜像。改了代码要 `brickkit build <id>`；镜像 tag 就是 `metadata.version`，版本号没升就会复用旧镜像（升版本，或者 `--force`）。
- **一次只跑一个组件。** `brickkit up --focus <id>` 从源码拉起这个组件和它需要的一切；`brickkit up --all` 回到整个项目。
- **然后对着它测。** `make test-cross ID=<scope>/<name>` 让组件的跨组件测试打到真实的依赖容器（[testing.zh.md](testing.zh.md#跨组件测试)）；项目里新加了组件之后跑 `make tier0`。
- **容器默认关着。** `make up` 管的基础资源（PostgreSQL、NATS、Casdoor……）可以常开；项目的组件容器只在真机验证和演示时需要，用完 `brickkit down`（不删 volume）。一直开着的容器在下次改动后跑的是旧版本，还会和本地测试抢同一个 NATS subject 的消息。
- **拆回验证。** 外壳合并之后，每个组件仍然必须能独立运行。`brickkit up --ignore-shells --dry-run` 不启动任何东西就能检查；`make teardown-up` / `make teardown-down` 把每个成员都当独立容器真的跑一遍。外壳的成员清单一变就跑。
- **在 IDE 里调试**用 `deploy.local.yaml` 里的 `mode: debug`（先 `brickkit local on`），绝不写进 `deploy.yaml`。

## 版本号

- **每次改动都升版本号**，只改测试或文档也一样。`component.yaml` 里的版本、Git tag、镜像内容三者必须始终一致：`component.yaml` 会被拷进镜像，而 `brickkit build` 会跳过已有镜像的版本。
- **先升版本，再动手。** 一开始就把 `metadata.version` 升上去，发布之前随便改；已经发布的版本绝不原地修改。
- 版本号必须精确（`2.0.0`）。组件在 `2.x` 线上，外壳在 `1.x` 线上。
- **Go 组件在同一个提交上打两个 tag**：给 brickKit 的 `2.0.0`（不带 `v`）和给 Go 工具链的 `v2.0.0`。模块路径以主版本结尾（`…/v2`），随主版本一起变。
- **外壳**在本仓库的 `shell/<scope>/<name>/` 下，tag 是本仓库里的 `<scope>-<name>/<版本>`。
- **用工具传播，不手工找。** 把这次会话里真正改了的组件全部写进一份计划文件，先 `make bump-version PLAN=<文件>`（只打印连锁影响，不写盘），再 `make bump-version PLAN=<文件> APPLY=1`。它会改写下游组件的 `component.yaml`（`dependencies` 以及外壳的 `shell.members`）和外壳的 `go.mod`。项目这边先 `brickkit upgrade <id>@<版本> --dry-run`，再去掉 `--dry-run`；它会让 `brickkit.yaml`、部署文件和 `config/` 保持一致。最后跑 `brickkit up --dry-run`：能发现版本漂移的是这条命令。
- 一批改动一份计划：每个组件单独跑一次工具，同一个下游会被升两次。

## 发布

按 `bump-version` 打印的顺序，逐个组件：

1. 它自己的测试和门禁全绿。
2. 在组件仓库提交并推送。
3. `brickkit release --notes-file <文件>`。说明文件放在组件目录之外（目录里的未跟踪文件过不了干净检查）。发布说明先写使用方必须做什么（某个键的含义变了、某个接口删了），再写新增了什么。
4. Go 组件：`git tag -a v<版本> -F <同一份说明>`，再 `git push origin v<版本>`。
5. `brickkit build <id>`。镜像只在本地构建，从不推送。
6. 回到本仓库：提交 submodule 指针和 `brickkit upgrade` 改出的内容，真机跑一遍，`brickkit down`。

`version-bump-ship` skill 会带着走完这一串，并写明什么时候该停下来问人而不是继续。

- 只为测试做的版本只打本地 tag，从不推送，测完删掉。
- 只有已经有文件等着推的时候才新建 GitHub 仓库；新建或删除任何仓库之前先告诉维护者。
- `brickkit remove` 会删掉组件源码：先提交并推送。
- Fork 出来的组件保留原来的 `metadata.id`：所有依赖方的地址变量都由它推导。
- 平台行为不对时，写出复现、报给 brickKit；绝不在组件里绕过去。
