# 阶段 06 待验证清单

本文件只给本项目自己用：记录"可能是 brickKit 的问题，但要等结构和文档按 v1 重建完、真机验证之后才能下结论"的疑问。验证成立的，再整理成条目搬进 `brickkit-feedback/phase-06.md`（那个文件是直接给 brickKit 看的，只放已验证的条目）。验证不成立的，在这里划掉并写一句原因。

| 编号 | 疑问 | 什么时候验 | 怎么验 | 结论 |
|---|---|---|---|---|
| V-01 | 重建完之后还需不需要驼峰配置键？v1 原样注入键名，驼峰键会被接受、不报警告。如果重建后全部改成大写下划线、没有任何需要驼峰的场景，这条就不成立 | 06b 第一个组件迁移完 | 看重建后的 configSchema；再故意留一个驼峰键跑 `lint` / `up`，看是否静默 | |
| V-02 | `AGENTS.zh.md` 在 lint 里会被怎么处理（规范说 AGENTS.md 不翻译） | 06a 项目 AGENTS.md 落地后 | 项目和一个组件各放一份 `AGENTS.zh.md`，跑 `brickkit lint --strict` | 已验（06a Task 14，CLI v1.0.1，记录 dev/test-records/06a/task14-agents-lint.md）。项目根 `AGENTS.zh.md`：完全不检查（故意放的 TODO、断链都无警告，也不要求 AGENTS.md 链它）。组件 `AGENTS.zh.md`：当译文检查——查 TODO、断链，要求 AGENTS.md 顶部链它，`DOC_TRANSLATION_DRIFT` 数小节时把维护块的 `## BrickKit` 算进主文件，所以译文必须补一节 `## BrickKit` 才过 `--strict`。与 skill 的"AGENTS.md is not translated"不一致，算反馈候选 |
| V-03 | 构建上下文不能越出组件目录。一个外壳仓库（一份代码、一个镜像）对应多个外壳实例的布局能不能用 `brickkit build` | 06a 外壳按 v1 重建后 | 先按 `brickkit new --shell` 的标准布局重建，确认是否真的需要"一个镜像、多个实例"，需要的话实测 | 部分已验（06a Task 8，CLI v1.0.1，记录 dev/test-records/06a/task8-shells-zero-members.md）。标准布局下一个外壳一个目录、一个镜像，不再需要"一个镜像、多个实例"，构建上下文不用越出外壳目录；4 个外壳目录 `docker build` 都能构建，零成员（`BRICKKIT_SERVED_MEMBERS_CONFIG=[]`）启动、`/healthz` 200。但 `shell.members: []` 被 `lint`/`add` 拒绝（`MANIFEST_INVALID`："a shell must list at least one component compiled into it"），外壳加不进项目，`brickkit build` 本身没跑成；`brickkit build` 是否顺利改到 06b 第一个成员加入时验。"零成员运行期合法、清单层面非法"算反馈候选 |
| V-05 | "只要地址自动注入、不锁版本"的依赖关系是否缺失：authz / iam 的地址如果走依赖边，精确版本锁定会让 authz 每发一版都连带 12 个组件发版；目前方案是改用 `config/vars.yaml` 的 `$var:` 集中写一处 | 06e 部署矩阵跑完 | 看 `$var:` 方案在独立 / 外壳 / k8s 各拓扑下需要改几处、是否别扭；确认 brickKit 没有现成机制 | |
| V-06 | Go 生态和 brickKit tag 规则冲突：brickKit 版本 tag 不带 v（`2.0.0`，`v2.0.0` 不算版本），Go 模块要求带 v，且 v2 及以上要改模块路径 `/v2`；Go 外壳通过 `go mod download` 拉成员源码，所以每个 Go 组件每次发版都要打双 tag | 06b 第一个 Go 组件发布、第一个 Go 外壳构建后 | 实际走一遍 `brickkit release` + `git tag v2.0.0`，记录摩擦点；确认 brickKit 有没有现成办法（比如 release 时顺手打 Go tag） | |
| V-07 | 版本漂移只被 `brickkit up --dry-run` 拦住，`brickkit lint` 一种都拦不住；而且"brickkit.yaml 版本与 component.yaml 不一致"只在 `.brickkit/manifests` 缓存不存在时才被拦——缓存可能掩盖本地源的版本变化（证据：dev/test-records/06a/task10-version-checks-experiment.md） | 06b 第一个组件升版时 | 在真实项目里先 `up --dry-run` 让缓存生成，再改 component.yaml 版本，看 lint / up 是否发现；确认是有意设计还是缓存失效问题 | |
| V-08 | 外壳合并部署下，成员的 Prometheus 指标怎么抓取：成员各自的 HTTP 端口上有 /metrics，但外壳的 labels 只能声明一个 prometheus.io/port；v1 起成员 labels 不再合并进外壳 | 06e 部署矩阵（开 obs 的那一格） | 合并部署 + make obs-up，看 Prometheus 能否拿到每个成员的指标；不行的话设计方案（外壳聚合 /metrics，或请 brickKit 支持多端口抓取声明） | |
| V-04 | 知识缺口：只靠已安装的 5 个 skill、项目 AGENTS.md 的 CLI 维护块、`.brickkit/manifests/` 缓存和 `--help`，能不能完成组件开发和部署 | 06a 用 `brickkit init` / `skills update` / `new` 重新生成之后，贯穿 06b–06f | 每次不得不去翻 brickKit 仓库，就在下面的缺口记录里追加一行；阶段末整理成反馈 | |

## 知识缺口记录（V-04）

从 06a 用 brickKit 命令重新生成项目文件之后才开始记。生成之前读 brickKit 仓库是在做迁移规划，不计入。

| 日期 | 缺的知识 | 当时在做什么 | 实际去读了哪里 | 建议用什么形式下发 |
|---|---|---|---|---|
| 2026-10-01 | 外壳成员在网络上如何寻址（成员服务名是否作为外壳服务的网络别名） | 06a Task 11 重写 seed-net.sh / test-cross.sh 的寻址逻辑 | brickKit 源码 internal/compose/servedby.go | brickkit-deploy 或 brickkit-component skill 的外壳一节写明：成员的服务名是外壳容器的网络别名，调用方照常用成员服务名 |
| 2026-10-01 | BRICKKIT_SERVED_MEMBERS_CONFIG 每项的确切字段名（componentId / version / httpPort / extraPorts / config） | 06a Task 5 实现 Go 外壳的成员解析 | brickKit 源码 internal/shell/shell.go（docs/en/04-shell/02-json-injection.md 有示例，但项目里装的 skill 没有） | brickkit-component skill 的外壳一节附一份完整 JSON 示例和字段表 |
| 2026-10-01 | mode local / debug 的宿主机端口映射规则（优先 10000+容器端口，冲突时从 18080 递增）是否仍成立 | 06a Task 13 写 registries.md 的端口段划分 | brickKit 源码 internal/compose/local.go | brickkit-deploy skill 的 local/debug 一节写明宿主机端口如何分配、项目应避开哪个端口段 |
| 2026-10-01 | BRICKKIT.zh.md 的章节标题必须用规定的中文名（组件定位/部署前准备/依赖说明/配置指南/契约索引/外壳声明），不能自由翻译 | 06a Task 8 写外壳文档 | 只能从 lint 报错反推（未读源码） | brickkit-component skill 的文档规则表列出每节的 en/zh 标准标题 |
| 2026-10-01 | DOC_LINK_NOT_PORTABLE 也检查组件 AGENTS.md 里指向 `../` 的链接，不只 BRICKKIT.md | 06a Task 8 写外壳 AGENTS.md | 只能从 lint 报错反推 | 同上，在 skill 里写明哪些文件受这条约束 |
| 2026-10-01 | focus / local 运行时组件的端口如何分配、`host.docker.internal` 在本机进程里如何解析、生成的服务名规则 | 06a Task 17 写单组件闭环清单的 focus 运行步骤 | brickKit 源码 internal/compose/local.go、internal/cli/up_local.go、internal/deploy/naming.go | brickkit-deploy skill 的 focus / local 一节补充：端口分配规则、本机进程如何访问容器里的依赖、服务名推导规则 |
