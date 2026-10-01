# 阶段 06 设计：按 brickKit v1.0.0 重建项目并大规模验证

> 开发文件（`dev/`），阶段结束后整体归档。正式文档不得链接本文件。
> 设计日期：2026-10-01。所有决策都经用户在 brainstorming 中逐条确认。

## 1. 背景与目标

项目基于 brickKit v0.4.6 构建，共有 14 个业务组件、4 个外壳（2 个外壳仓库）、5 个工具仓库。brickKit 现已发布 1.0.0，引入三层模型、组件文档规范、Podman、local 模式等，并且**不兼容 0.x**。本机 CLI 已经是 v1.0.0，旧的 `brickkit.yaml` 被判为非法。本项目是 brickKit 唯一的使用者，因此不做逐字段迁移，**直接用 v1 的命令和规范从头重建**。

本阶段有三个目标：

1. **重建**：所有组件、外壳、工具链、文档都按 brickKit v1 的规范和理念重建，并借助更强的模型把代码（尤其是前端）打磨得更好。
2. **验证**：在重建后的项目上大规模验证 brickKit，包括 AI 能否读懂项目、全部部署形态，以及其余可测的功能。
3. **反馈**：把验证中得到的真实问题整理好交给 brickKit。

**成功标准**

- `brickkit lint --strict` 在项目和每个组件仓库中都零警告；`make gates` 和 `make docs-boundary` 全绿。
- 14 个组件都是 2.0.0，4 个外壳都是 1.0.0，全部已真实发布（tag 已推送）；业务闭环（商机赢单 → 订单 → 库存 → 应收）在重建后的系统上跑通。
- AI 路由测试总分 ≥ 90%，"与已有决策冲突"类 100%。
- 部署矩阵 18 格加专项格全部有过程记录；local 文件与 debug 测试线、剩余功能测试全部有过程记录。
- 反馈信箱中的每一条都有原始证据；复盘已写完。

**工作原则**

- **以最终目的为主。** 过渡状态下的临时问题不修。重构是常规操作，结果追求完整、理念最优。
- 遵循已有记忆：每完成一个检查点就停下汇报；语言、构建机制这类没验证过的东西，先做最小复现；对外宣称"已修复"之前，自己先复测。

## 2. 已定决策

| 主题 | 决策 |
|---|---|
| 版本 | 保留全部仓库、历史和旧 tag。组件统一升到 **2.0.0**，外壳升到 **1.0.0**。`component.yaml` 中的版本注释全部删除，历史以 git 和 tag 的发布说明为准 |
| 文档归属 | 正式文档（给 AI 和使用者看）只写结论，**绝不链接 `dev/` 或 `archive/`**。开发过程中的文件放进 `dev/`，阶段结束后整体归档。旧文档放进 `archive/pre-v1/` 冻结 |
| 决策文档 | 只有约束未来改动的大决策（15–25 条）作为正式文档放进 `docs/decisions/`，小决策随旧文档归档 |
| 规范重复 | 项目约定与 brickKit 通用规范面向的读者不同，允许重复。旧规范文档中能复用的部分改写后复用 |
| 语言 | 英文为主文件，同目录放 `.zh.md` 译本；项目和组件的 `AGENTS.md` 也保留中文版。和用户聊天始终用中文 |
| 前端 | 技术栈（Vue 3 + AntDV v4 + vxe-table / wot-design-uni）和两层导航不变；重做视觉，补全功能，加入 i18n 和 E2E 测试 |
| 推进方式 | 地基先行，组件逐个闭环：06a → 06b → 06c → 06d → 06e → 06f |
| 外壳 | 外壳改为项目代码，放在 `shell/` 下，用 `brickkit new --shell` 生成，每个外壳对应一个镜像和一份成员清单。`shells/go`、`shells/python` 两个 submodule 退役。启动器代码下沉到 SDK |
| 共用配置 | 多个组件重复使用的值（数据库主机、NATS、authz/iam 地址等）统一放在 `config/vars.yaml`，组件通过 `$var:` 引用。组件有特殊需要时，在自己的 config 中覆盖 |
| authz/iam 地址 | 不走依赖边（精确版本锁定会导致连锁发版），改用 `$var:` 集中维护，一处修改即可。不同拓扑在各自部署文件的 `vars:` 中覆盖 |
| 发布 | 真实版本用 `brickkit release` 打 tag 并推送。测试用的版本只打本地 tag，永不推送，测完删除。镜像只在本地构建，不推送。新建或删除 GitHub 仓库前先提醒用户 |
| 反馈 | `brickkit-feedback/`（已加入 gitignore 的信箱）只放重建后真机验证过的条目，不提迁移或兼容性问题。未验证的疑问先记入 `dev/phase-06/to-verify.md` |

## 3. 目标目录形态

```
AGENTS.md (+ AGENTS.zh.md)   正式：项目概述 / 项目约定 / 查找路由 / 易错点 + CLI 维护块（lang=en）
CLAUDE.md                    @AGENTS.md
README.md (+ .zh.md)         给人看的入口
brickkit.yaml                声明层（锁文件）
deploy.yaml                  团队部署文件；deploy.<env>.yaml 用于其它环境和拓扑
config/vars.yaml             共用变量；config/<scope>-<name>.yaml 每个组件一份
.claude/skills/              5 个 brickKit skill + 项目自己的 skill（version-bump-ship 按 v1 重写）
docs/
  decisions/NNNN-*.md        大决策：结论 + 两三句理由
  conventions/*.md           项目约定细则（由旧 standards 改写：SOP、测试分层、数据构造、文档、AI 开发、参考实现、权限键、登记表）
  ops/*.md                   部署手册、部署形态选择（以 06e 的结果为依据）、可替换性地图
  seed-data.md               种子数据一览
registry/  infra/            保留；登记表照旧只追加不修改
components/<scope>/<name>/   submodule；组件四件套（各带 .zh.md）+ docs/design.md（只写结论）
shell/<scope>/<name>/        外壳，项目代码（路径以 brickkit new --shell 的实际输出为准；外壳 ID 的 scope 在 06a 定）；
                             tag 格式为 <scope>-<name>/<ver>
tools/                       be-ops、be-acceptance、be-sdk-{go,python,ts}
dev/                         开发工作区：phase-06/（spec、plan、to-verify、component-loop、batches/、retrospective）、
                             routing-tests/、test-records/  → 阶段结束后归档
archive/pre-v1/              旧 docs/ 整棵树、设计书、旧 AGENTS.md/.zh.md、旧 brickkit.yaml，按原结构冻结
brickkit-feedback/           被 gitignore 忽略：与 brickKit 沟通用的信箱
```

**正式文档的边界由 `make docs-boundary` 把关**：扫描根目录 `AGENTS*.md`、`README*.md`、`docs/` 和各组件的文档，发现链接指向 `dev/` 或 `archive/` 就报红，并接入 `make gates`。组件文档另由 `brickkit lint --strict` 检查。

**正式文档中的项目级内容来源**

- 旧 AGENTS.md 的"23 条易错"中，v1 下仍然成立的条目放进"易错点"；已被 v1 改变或删除的条目（旧第 5、6、9、10、12、13、14 条等）删除。
- 踩坑记录中仍然成立的条目，提炼进项目或组件 AGENTS.md 的易错点表。
- 旧 standards 和总纲改写后放进 `docs/conventions/`。

## 4. 06a 地基

1. **归档**：把旧的 `brickkit.yaml`、`docs/`、设计书、`AGENTS.md`/`AGENTS.zh.md` 移入 `archive/pre-v1/`；删除 `.brickkit/`。
2. **用 CLI 重新生成项目文件**：`brickkit init`，然后 `brickkit skills update`。`.gitignore` 按 v1 的要求补齐（整个 `.brickkit/`、`deploy.local.yaml*`、`.secrets/`、`.env`、`config/.archive/`）。pre-commit 改用 `brickkit init --hooks`，项目自己的检查并入同一个 hook。06a 结束时 `brickkit.yaml` 中没有任何组件。
3. **写项目级正式文档**：在 CLI 生成的骨架上写项目 AGENTS.md 的四节（含中文版），以及 `docs/conventions/`、`docs/decisions/`。`docs/ops/` 等 06e 结束后再写。
4. **定配置约定**：
   - 键名一律大写下划线；
   - 统一的连接键：`PG_HOST`、`PG_PORT`、`PG_DATABASE`、`PG_USER`、`PG_PASSWORD`（`secret: true`）、`PG_SCHEMA`、`NATS_URL`、`S3_URL` 等，避开保留后缀 `*_ENDPOINT`；
   - `config/vars.yaml` 的初始内容；
   - 每个组件自己的密钥写成 `${…}`，从环境变量或 `.env` 读取。
5. **SDK**：be-sdk-go、be-sdk-python、be-sdk-ts 改为读取新键名，不再依赖平台注入的资源变量；适配新格式的 `BRICKKIT_SERVED_MEMBERS_CONFIG`（`config` 字段）；新增 shell 包（成员加载、共享连接池、panic 隔离）。各升一个小版本并发布。
6. **工具链**：
   - be-ops：删除 genyaml；端口/schema 登记检查、建库脚本、权限键汇总、Traefik 路由、菜单汇总逐项复核，保留仍有用的；菜单汇总在 06c 补全实现。
   - be-acceptance：保留与 brickKit 无关的 gate；`dependency-version-scan` 和 `bump-version` 先实测 v1 的 `lint`/`up`/`upgrade` 能覆盖多少，再决定删减范围；tier1 断言放到 06f 重写。
   - Makefile 和 `infra/scripts`：teardown 改用 `--ignore-shells` 或单独的部署文件；删除 `patch-teardown-bindings.py`；按新的生成目录（`compose.yaml`）重写 `arsenal.sh`、`seed-net.sh`、`test-cross.sh`。
   - 新增 `make docs-boundary`。
7. **外壳骨架**：用 `brickkit new --shell` 在 `shell/` 下生成 go-core、go-infra、go-backoffice、py-render。成员要等 06b 对应批次完成后再填入。
8. **前端需求盘点**：整理"页面和操作 → 依赖的组件接口 → 接口是否已存在"对照表，写入 `dev/phase-06/frontend-needs.md`。缺失的接口在 06b 重建对应组件时补上。
9. **AI 路由题库**：在 `dev/routing-tests/` 下编写约 30 道题，见 §7。
10. **单组件闭环清单**：写好 `dev/phase-06/component-loop.md`，见 §5。

**检查点**：06a 完成后停下汇报。

## 5. 06b 组件逐个闭环

**单组件闭环**（每个组件都按这个流程做，清单见 `component-loop.md`）：

1. 前置条件：它的上游组件都已重建完成，并已加入项目。
2. 在临时目录运行 `brickkit new <id>` 拿到 v1 骨架，用骨架替换组件仓库中的旧文档（README、AGENTS.md、`docs/手册.md`）。代码保留。
3. 重写 `component.yaml`：
   - 删除版本注释；
   - 补上 `metadata.repository` 和 `deployment.build`；
   - `configSchema` 改为大写下划线键，采用统一连接键，密钥标 `secret: true`；
   - 依赖改为上游的 2.0.0；
   - 删除 `resources`；
   - 端口和 schema 照抄 `registry/`。
4. 代码：升级 SDK，改为读取新键名；做一轮审查（正确性、超长文件、重复样板代码），只修真实问题，不改业务行为；补上前端需要的接口；L1–L4 测试全部通过。
5. 文档：编写 `BRICKKIT.md`、`AGENTS.md`、`README.md`、`docs/design.md`，各带 `.zh.md`。`docs/design.md` 从 `archive/pre-v1/` 中的旧组件设计文档提取结论。
6. 版本改为 2.0.0，在组件仓库中运行 `brickkit lint --strict`，要求零警告。
7. 接入项目：
   - `brickkit add` 把组件加入项目，用 `$var:` 填写 `config/<id>.yaml`；
   - `brickkit build <id>` 构建镜像；
   - `brickkit up --focus <id>` 把它和强依赖树一起拉起来；
   - 运行 `make test-cross` 和冒烟测试。
8. 发布：在组件仓库提交，用 `brickkit release --notes-file` 发布；父仓库更新 submodule 指针。
9. 记录：过程写入 `dev/phase-06/batches/`；知识缺口记到 to-verify 的 V-04。

**批次**

| 批次 | 组件 | 完成后组装的外壳 |
|---|---|---|
| B1 试点 | mdm/customer → mdm/product | — |
| B2 | infra/authz → infra/iam-casdoor | — |
| B3 | infra/workflow、infra/notification、integration/im-dingtalk | go-infra |
| B4 | erp/inventory、erp/finance、infra/print | py-render |
| B5 | erp/sales、crm/opportunity | go-core、go-backoffice |
| B6 | infra/bff-mobile | — |

外壳组装完成之前，成员组件独立运行。外壳组装：在 `component.yaml` 写好 `shell.members`，在 `deploy.yaml` 写好 `members`，运行 `brickkit build`（镜像带成员标签），然后发布 1.0.0。

**检查点**：mdm/customer 完成后单独停一次（它是后续 13 个组件的样板），之后每个批次结束停一次。

## 6. 06c 前端

- `frontend/standard` 走一遍单组件闭环（升 2.0.0，四件套）。
- **视觉方向**：先用 frontend-design 方法做 2–3 套真实页面效果图（同一个列表页和仪表盘），在浏览器里给用户选，选定后再铺开。设计令牌保持为运行时可切换的 CSS 变量，亮色/暗色和两档密度都要真实可用。
- **功能补全**，以 `frontend-needs.md` 为准：
  - PC：仪表盘；客户和产品的增删改；订单的新建、确认、取消；库存的入库和调整；财务凭证；商机的列表、详情、阶段推进、赢单转订单；打印模板管理和预览；通知偏好。
  - 移动 H5：审批、通知、订单查询、库存查询、商机速览。
  - 中英文 i18n。
- **菜单**：用 be-ops 从各组件的 `assembly.yaml` 汇总菜单，替代手写的 `menuRegistry.ts`。
- **测试**：补齐 FE-1/FE-2；FE-3 用 Playwright 在真实后端上测主链路（登录、建单、审批、赢单转订单）；FE-4 对关键页面的亮色和暗色截图建立基线。

**检查点**：视觉方向选定后停一次，06c 完成后再停一次。

## 7. 06d AI 路由测试

- **题库**（`dev/routing-tests/questions.md`），约 30 题，分 6 类：只改一个组件；需要先改上游；需要新组件；与已有决策冲突；部署与配置；排障。另加一类"外部使用者视角"：只提供某个组件的 `BRICKKIT.md`，回答怎么用、部署前要准备什么、配置怎么选。
- 每题都写明：期望的阅读路径（文件 + 章节）、plan-change 的期望结论（四种之一）、标准答案、禁止阅读的范围（`dev/`、`archive/`、依赖方源码、brickKit 仓库）。
- **考法**：每道题交给一个零上下文的子 agent，Opus、Sonnet、Haiku 各考一遍。子 agent 只知道项目路径，要求它按顺序记录读过的文件。
- **评分**：分路径、结论、答案三个维度。总分 ≥ 90%，冲突类 100%（必须停下来问人）。
- 答错的题对应修改文档；改完重考错题，再随机抽几道已答对的题做回归。每轮结果记入 `dev/routing-tests/runs/`。

**检查点**：06d 完成后停下汇报。

## 8. 06e 部署矩阵

**基础矩阵**：6 种运行形态 × 3 种拓扑，共 18 格。

| 运行形态 \ 拓扑 | 全部独立 | 全部合并进外壳 | 混合（部分成员移出外壳） |
|---|---|---|---|
| Docker | | | |
| Podman | | | |
| Kubernetes (minikube) | | | |
| 纯 local（所有组件都是 brickKit 托管的本机进程，基础设施是容器） | | | |
| Docker + 本机进程 | | | |
| Podman + 本机进程 | | | |

"+ 本机进程"指一部分组件或外壳以 `mode: local` 运行，其余跑在对应引擎的容器里，重点验证进程和容器之间的双向调用。debug 与 local 的逻辑相同，不纳入矩阵。

**专项格**：Podman rootless 的 AppArmor 问题；k8s 的 `podSecurity: restricted` 和 `networkPolicy`；k8s 上的密钥（`file://`、`existingSecret`）；用 `-f deploy.<env>.yaml` 加 `vars:` 覆盖实现多环境；同一组件多版本并存（`requiredBy`）；版本错位；focus 运行。

**每格的流程**：`up` → 健康检查 → 种子数据 → 跑通业务闭环 → `down`。

**local 文件与 debug 测试线**（独立于矩阵）：
- `deploy.local.yaml` 的生命周期：`local on`、`off`、`status`、`refresh`；整份替换而非合并；团队新增组件后 `up` 要求先 refresh，refresh 生成 `.bak` 并列出本地改动；`--no-local`；`focus:` 字段；`mode: debug` 写进 `deploy.yaml` 时被拒绝。
- debug 实测：把一个组件设为 debug，由 AI 用生成的 `local-debug.*.env` 自行启动它（模拟在 IDE 中调试），验证三点：它能调用容器中的依赖；容器中的上游能调用它；外壳成员切到 debug 后会离开外壳，外壳内其余成员不受影响。

矩阵跑完后，以结果为依据重写 `docs/ops/`。

**检查点**：矩阵完成后停一次，local 测试线完成后停一次。

## 9. 06f 剩余功能、反馈、复盘

- **逐项验证**：
  - `skills status` / `update`、`lang set`、`completion`、`graph`、`deps`；
  - `upgrade`：逐键迁移配置、冲突时写成重复键、展示发布说明；
  - `release`：`--local`、`--notes`，以及推送失败时回删 tag；
  - `remove` 后再 `add`，从归档中恢复配置；
  - `sync`、`restore --check`、hooks；
  - `lint --strict`：故意制造 11 种文档错误，逐一确认都能报出；
  - `build --force`、`IMAGE_STALE`、`IMAGE_UNVERIFIED`；
  - 本地 market-server 上的 `publish`（附带 `BRICKKIT.zh.md`）；
  - Git 安装源（用本地 bare 仓库模拟 `baseUrl`）；
  - workbench（`add --local --init`）；
  - 嵌套组件检测；
  - did-you-mean 拼写提示。
- 长期有效的断言写进 be-acceptance 的 tier1，替换旧的 23 条。
- 把 to-verify 中已成立的条目整理进反馈信箱。
- 写复盘 `dev/phase-06/retrospective.md`；阶段结束后把 `dev/phase-06/`、`dev/routing-tests/`、`dev/test-records/` 归档。

**检查点**：06f 完成后停下汇报。

## 10. 过程记录规范（所有测试通用）

每个测试格、每个功能点各写一份记录，路径为 `dev/test-records/<测试线>/<格子>.md`：

```
目标 / 环境（brickKit 版本、目标、拓扑、组件版本）
步骤：每条命令 + 关键输出原文（不截断、不只取 tail）+ 耗时
现象：符合预期的 / 不符合预期的
卡点与绕过：卡在哪、怎么排查的、读了哪个 skill / 文档 / --help、是否不得不翻 brickKit 仓库
结论
反馈候选：→ to-verify 还是直接进信箱，以及理由
```

复盘和反馈都直接从这些记录中提炼。

## 11. 版本与发布规则

| 情况 | 做法 |
|---|---|
| 真实版本 | 组件 2.0.0；外壳 1.0.0（tag 格式 `<scope>-<name>/1.0.0`）；工具仓库各升小版本并打带注释的 tag。统一用 `brickkit release --notes-file` 发布（工具仓库不是 brickKit 组件，沿用 `git tag -a` 加推送） |
| 后续改动 | 遵循语义化版本，用 patch 或 minor；下游依赖版本用 `brickkit upgrade` 加 bump 脚本同步 |
| 测试用版本 | 只打本地 tag，永不推送，测完删除 |
| 镜像 | 只在本地 `brickkit build`，不推送 |
| 仓库增删 | 先提醒用户（本阶段已知：`shells/go`、`shells/python` 两个 submodule 退役） |
| 提交 | 组件仓库每个组件一个提交；父仓库每个批次一个提交；大任务完成后主动提交一次 |
| 提交信息 | 较长或含引号的提交信息先写入文件，再用 `git commit -F`；提交后先看 `git log`，再打 tag |

## 12. 风险与应对

| 风险 | 应对 |
|---|---|
| 06b 全部完成之前，整个系统无法完整运行 | 用 focus 运行逐个组件验证；没被外壳收编的成员按独立组件部署 |
| SDK 的 shell 包是新机制，一次铺开到多个仓库风险大 | 先在一个外壳加两个成员上做最小复现，跑通后再推广 |
| 试点组件定下的模板有问题，会被复制 13 遍 | mdm/customer 完成后单独设检查点，由用户审阅 |
| 外部仓库或推送出错（tag 打在错误的提交上等） | 遵守 §11 的提交信息规则；`brickkit release` 推送失败时会自动回删 tag |
| 测试中容器之间相互干扰（如争抢同一订阅主题） | 每格测完都 `down`；测试库和演示库在物理上分开 |

## 13. 不在本阶段范围内

- 新的业务组件（如采购）。
- 推送镜像。
- 修改前端技术栈。
- 迁移或兼容 0.x 的任何工作。
