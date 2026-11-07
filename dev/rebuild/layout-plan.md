# 组件代码按业务分层的计划

> 2026-11-07 维护者提出：现在每个组件的代码平铺在一个文件夹里，要改哪里得先把全部文件扫一遍。要一个以业务为主轴的结构（DDD 的思路）：每一层放一份说明，进入下一层之前先读它，就知道哪些是要关心的、哪些不是；测试同理，按结构组织，读一份文档就知道哪些测试测什么。
>
> 按 `f-plan`。设计的决定是 AI 定的（A160–A163，待复核），先拿 `erp/sales` 试点，**维护者看过试点再铺开**。

## 现状

| 组件 | 主包 | 文件 | 行数 | 测试文件 |
| --- | --- | --- | --- | --- |
| `infra/authz` | `authz/` | 68 | 14041 | 36 |
| `erp/sales` | `sales/` | 25 | 6256 | 6 |
| `infra/iam-casdoor` | `iam/` | 22 | 3800 | 9 |
| `erp/billing` | `billing/` | 15 | 2888 | 5 |
| `erp/inventory` | `inventory/` | 14 | 2863 | 3 |
| `mdm/org` | `org/` | 13 | 2232 | 4 |
| `infra/audit` | `audit/` | 12 | 1916 | 6 |
| `mdm/product` | `product/` | 11 | 1809 | 3 |
| `mdm/partner` | `partner/` | 10 | 1608 | 3 |
| `erp/credit` | `credit/` | 9 | 1842 | 3 |
| `mdm/currency` | `currency/` | 9 | 1388 | 3 |
| `infra/print`（Python） | `infra_print/` | 13 | — | — |

规范（[标准布局](../../docs/zh/01-conventions/05-ai-navigation.md#组件仓库的标准布局与代码地图)）写的是“一个包、按业务分文件”，另有一句“长到某一块有自己的规则与测试时拆子包”，但没有门槛、没有检查，于是从没拆过；代码地图写在仓库根的 `AGENTS.md` 里，一张表列全部文件。

不在范围：没有重建的 2.x 组件（`crm/opportunity`、`erp/finance`、`infra/workflow` 等，重建时直接按新结构写）；SDK 与工具（它们已经按包分开，有包说明；最后一个任务单独评估大包）。

## 设计（AI 定，待复核）

依据：kb `01-architecture/04-application-architecture/00-decisions.md` 的 D2（按业务模块切，不按技术层）与 D5（边界靠检查，不靠文档）；`01-fundamentals/13-ai-friendly-architecture.md`（上下文局部性、可预测的结构、护栏即代码）。定稿的规则在规范 05 的[标准布局](../../docs/zh/01-conventions/05-ai-navigation.md#组件仓库的标准布局与代码地图)，这里只记设计的来由与铺开时的取舍。

### 目录（A160）

```text
<仓库>/
├── AGENTS.md            第 1 层：组件做什么；目录表、业务模块表、“想改什么从哪里开始”；测试在哪
├── <包>/                第 2 层：组件的入口与组装（包名不变，main.go 与外壳照旧只引用它）
│   ├── AGENTS.md        怎样把模块组装起来
│   ├── definition.go    端口、迁移、配置键、组件定义（名字、资源与操作从 internal/core 收集）
│   ├── module.go        只组装：建 core.Base，登记路由、作业、订阅、启动、重放
│   ├── services.go      系统面的登记与转发；checks.go 恢复核对
│   └── migrations/      表（整个组件一套，不按模块拆：迁移顺序是全组件的）
├── internal/            第 2 层：业务。Go 的 internal 只给本仓库引用，别的组件编译期就引用不了（落实决定 0101）
│   ├── AGENTS.md        模块表（一句话、依赖）与分层、共同的写法
│   ├── <业务模块>/       第 3 层：一个业务模块一个包
│   │   ├── AGENTS.md    负责与不负责、文件、依赖与被依赖、规则在哪、测试
│   │   ├── *.go
│   │   └── *_test.go    这个模块的单元测试
│   └── core/ 等共用的    第 3 层：名字、资源与操作的定义（一张表）、记录与事件的写法、Base；上游的取证（masterdata）
├── itest/               集成测试（构建标签 integration）：按业务流程分文件
│   └── AGENTS.md        测试索引：每个文件测哪条流程、被测的模块、步的顺序、怎样跑
├── cmd/                 照旧
└── docs/                照旧（design.md 等：规则的正文；AGENTS.md 只指过去，不重复）
```

- **模块怎样切**：按业务能力（一个聚合或一条业务流程），每个模块有自己拥有的表与路由；以“改一个典型需求只动一个模块”为准，拿不准时宁可少切（kb D2 的翻转：过早划的边界改起来贵）。
- **资源与操作的定义是 `internal/core` 的一张表**（L1 改的：`erp/sales` 三种单据共用一张字段表与同一套维度，分到各模块要重复）；模块只引用操作的常量。模块不能反过来引用入口包，所以名字也在 `core`。
- **依赖只朝下**：模块的函数先收 `*core.Base`，模块之间直接调对方导出的函数，只引用比自己低的层；低层要通知高层时经 `Base` 上由入口接好的函数（`infra/authz` 的 `RecordMoved`），按种类分派到几个模块的路由单独成一个小模块（`infra/authz` 的 `confirmroutes`）。规则写进了规范 05。
- **`core` 之下可以有不依赖它的基础包**（`infra/iam-casdoor` 的 `provider`、`keys`）：规范要不要明写、检查要不要核对分层，见结构问题 SF08。
- **包的大小**：入口包只放组装；一个模块超过约 12 个文件或有两块各自的规则时再拆。拆不开的（`infra/authz` 的生效点）照实写进模块说明与结构问题登记（SF05）。

### 每层的说明（A161）

- 每个有代码的目录一份 `AGENTS.md`（同目录 `CLAUDE.md` 只写 `@AGENTS.md`：Claude Code 读到这个目录的文件时会自动带上它，正好是“进入下一层之前先读”）。
- 内容固定的几节，只写这一层的：**一句话**；**负责什么、不负责什么（去哪找）**；**文件**（每个文件一行）；**依赖与被依赖**；**规则在哪**（指 `docs/` 的节，不抄）；**测试**（哪个测试测什么）。每份控制在一屏左右。
- 仓库根的 `AGENTS.md` 的代码地图缩成目录表、模块表与“想改”表，不再列全部文件。

### 测试的结构（A162）

- **单元测试**跟着模块：放在模块目录里，只测这个模块；测试的辅助函数只在自己的包里用（各包各一份，SF22）。
- **集成测试**集中在仓库根的 `itest/`，按业务流程分文件，共用的启动与替身在 `itest/` 的公共文件里；原来一个大函数的，按段落拆成 `fixture` 的步骤。`itest/AGENTS.md` 是测试索引：文件 → 步 → 流程 → 被测的模块，步的顺序与能不能单独跑。
- 组件的 `Makefile`：`make test`、`make test-integration`（`./itest/`）。

### 检查（A163）

`make layout-check`（`infra/scripts/layout-check.py`，进 `make gates`，7 个测试：合格的过，六种改坏各报错）对每个已重建的 Go 组件核对：入口包、`internal/` 与其下每个包、`itest/` 都有 `AGENTS.md` 与只含 `@AGENTS.md` 的 `CLAUDE.md`；每份说明的“文件”一节与目录里的 `.go` 文件一一对应；入口包只有组装文件；集成测试只在 `itest/`；`internal/AGENTS.md` 模块表的依赖与 `go list` 的实际导入相同；组件根的代码地图列出每个模块。铺开期间未分层的组件列在 `PENDING` 里不查，L4 做完后连同 `ALL=1` 一起删掉。

## 任务

| # | 任务 | 依据 | 依赖 | 验收 | 状态 |
| --- | --- | --- | --- | --- | --- |
| L1 | **试点 `erp/sales`**：按上面的设计重排（3.0.39），行为不变；写各层的 `AGENTS.md`；集成测试搬进 `itest/` 并写索引 | A160–A162 | — | 单元与集成测试全过（与重排前同样的用例数）；`go vet`；`brickkit lint`；每个模块 `AGENTS.md` 的文件清单与目录一致；一个新会话只读文档能答出“改报价的取价改哪里、测在哪” | ✅ 2026-11-07（见“L1 的结果”） |
| L2 | **维护者看试点**：结构、文档的写法、测试的组织；照意见改，定稿 | L1 | L1 | 维护者确认 | ✅ 维护者 2026-11-07“先按这样铺开”：全部 Go 组件与 `infra/print` 做 L1；状态与不变量复杂的（`erp/inventory`、`erp/billing`、`erp/credit`、`infra/authz`）再做 L1b；铺开到 `infra/authz` 时用一道窄题前后各考一次 |
| L3 | **规范与检查**：改标准布局、测试与验证、改动配方；写 `make layout-check`（A163）并进 `make gates` | L2 | L2 | 检查对试点通过、对未改的组件报错；改坏全红 | ✅ 2026-11-07：规范 05（标准布局：Go 与 Python 的树、模块怎样切、每层的说明、布局检查）、06（新节“状态与不变量集中一处”）、02（测试放在哪、测试索引）、11（加一个功能放哪个模块、加一个状态或命令）；根 `AGENTS.md` 的查找路由加一行；检查与它的测试（当时其余 10 个组件共报 183 处）；`erp/sales` 3.0.40 已发布。样板：新组件照 `erp/sales`（规范 11 的“新建一个组件”）；`brickkit-component` 技能是 BrickKit 的通用做法，本项目的布局以规范为准，不改它 |
| L4 | **铺开到其余 Go 组件**，从小到大（先熟练、后难）；每个升最后一位版本、行为不变、测试全过、发布 | L3 | L3 | 每个组件：测试全过、断言条数前后相同、`make layout-check` 通过、发布 | ✅ 2026-11-07，10 个组件（见“L4 的结果”）；`PENDING` 已删 |
| L4b | **铺开的收尾**：依赖方（`erp/sales`、`erp/credit`、`erp/inventory`、`erp/billing` 对主数据与彼此）与外壳 `be/go-core`、`be/go-infra` 的钉版本统一换一次（见“铺开期间的版本”）；其余 11 个组件的合并安全测试扩到 `internal/` 下全部包（SF24，同一版一起发）；`infra/audit` 补 `Makefile`（SF09） | L4 | L4 | `make version-check`（含 `pin-check`）全过；每个组件的合并安全测试对 `internal/` 里放一个违规的探针会红；外壳构建通过 | ✅ 2026-11-07：`mdm/org` 3.0.31、`mdm/currency` 3.0.30、`mdm/partner` 3.0.34、`mdm/product` 3.0.33、`infra/audit` 3.0.35（补 `Makefile`，集成测试经它实跑）、`infra/iam-casdoor` 3.0.40（合并安全的测试从 `login` 挪到入口）、`erp/credit` 3.0.30、`erp/inventory` 3.0.30、`erp/sales` 3.0.41、`erp/billing` 3.0.39，外壳 `be/go-infra` 3.0.67、`be/go-core` 3.0.66；每个组件的探针都红过；`pin-check` 0 处、`version-check` 全绿；外壳 `go build`、`go vet`、单元测试通过，镜像的构建与运行留给 L6 的真机格。只改了单元测试与钉版本，没有重跑各组件的集成测试（`infra/audit` 除外） |
| L1b | 四个复杂组件的 L1b（见“L1b 的铺开”） | L1b（`erp/sales`） | L4b | 照 `erp/sales` 的 L1b-1 至 L1b-6 | ⬜ |
| L5 | **Python 的 `infra/print`**：同样的分层（Python 子包、`AGENTS.md`、`itest/`） | L3 | L3 | 测试全过、布局检查通过、发布、外壳 `be/py-render` | ✅ 2026-11-07：`infra/print` 3.0.15：入口 `infra_print/` 只组装（`__init__.py`、`__main__.py`、`module.py`），业务在 `templates`（随带模板与登记、版本与校验、路由）、`rendering`（工作进程池、工作进程、渲染、系统面与预览）；集成测试进 `itest/` 带索引；合并安全的单元测试改成扫包里全部模块（原来只扫顶层，同 SF24）；单元 8、集成全过；`make layout-check` 扩到 Python 组件（入口只组装、每层两份说明与文件清单、`integration` 只在 `itest/`、模块表对 `ast` 读出的导入），检查的测试加两例（9 个全过）；规范 05 的布局检查一段补 Python；外壳 `be/py-render` 3.0.42 |
| L6 | **真机格**：从空库起跑一个单跑格与一个外壳格（建格、种子两遍、L3 场景），确认重排没有改变行为 | L4b、L5 | L4b、L5 | 两个格全过 | ⬜ |
| L7 | **SDK 与工具里的大包**：评估 `be-sdk-go` 里文件超过约 15 个的包（`tiering/` 等）、`be-sdk-python` 的 `besdk/`（54 个文件，一层平铺加几个子包）与 `be-ops` 的 `internal/recovery/`：公开的接口不变，能否在包内按职责分 `internal/` 子包、配同样的每层说明；结论与做法写在这里 | L3 | L3 | 写出结论；要改的照同样的验收 | ⬜ |

## 做法（每个组件照这个做）

工具在 `layout-tools/`（说明见它的 `README.md`）；每个组件一个可重放的流水线（`layout-tools/pipelines/<组件>-pipeline.sh`），从仓库的 `HEAD` 起做完整个重排：

1. **定模块表与分层**：小组件读代码地图就够；文件互相牵连的（`infra/authz`），先用 `pkgrefs`（每个文件用到别的文件的哪些包级名字与 `Module` 的方法）与 `partition2.py`（给一种分法，算包之间的依赖与环）试分法，到无环为止，动手前写下模块表。只看包级名字会漏掉方法调用（`infra/authz` 第一次的分法就因此漏了两个环）。
2. **预拆**：把要去不同包的声明按包挪进各自的文件（`mvdecl`，按语法树挪声明连同注释；一个文件里同名的两个声明只挪得动一个，先改名）；被几个模块用的名字、工具函数、存储的方法挪进 `core`；导出后会与类型重名的方法先改名（`-rename`，或预拆时改）；`var ( … )` 块先拆开（`splitvars.py`）。
3. **按类型的改写**（`restructure`）：`Module` 的方法改成先收 `*core.Base` 的函数、被别的包用到的名字导出（导出的字段带 `json:"-"`，不改编码，见 SF07）、跨包的引用加包名；方法值报出来手接。
4. 挪进 `internal/<包>/`，`goimports` 补导入（自定义别名要先给：`aliases.py`，否则它会选错同名的包，例如 `pgx` v3、`jwt` v3、`alecthomas/assert`）；`Module` 除了运行时还带别的字段的，一起放进 `core.Base`。
5. **入口**的 `module.go`、`services.go`（`checks.go`）手写一次（`layout-tools/entry/`）。
6. **集成测试**搬进 `itest/`；原来一个大函数的，按段落拆成 `fixture` 的步骤（每条语句照搬，步骤之间共用的变量收进 `fixture`）。入口包里测的是某个模块函数的单元测试，跟着那个函数进模块。
7. 每一步后编译；最后 `go vet`（含 `integration`）、全部测试、前后对断言条数与测试名单；改名后的说明注释第一个词跟着改（`doccap.py`）；`Makefile` 的 `test-integration` 改成 `./itest/`（SF18）；写各层的说明，`make layout-check`、`brickkit lint`。
8. 旧代码的测试在干净的 worktree 里跑（`git stash` 留下未跟踪的新目录，会让旧代码编译失败、看起来像红）。

## L1 的结果（`erp/sales`，2026-11-07）

`erp/sales` 3.0.39，分支 `layout`：入口 `sales/` 5 个文件（定义、组装、gRPC 转发、恢复核对、单元测试），`internal/` 下 12 个包（8 个业务模块、4 个共用），`itest/` 11 个文件；每个目录一份 `AGENTS.md` 与 `CLAUDE.md`。单元与集成测试全过（用例与步骤 29 个，与重排前同一份名单）；`go vet`（含 `integration`）、`gofmt`、`brickkit lint` 干净；文件清单的原型检查（`filemap-check.py`）对试点通过、改坏两处（删一行文件、缺一份 `CLAUDE.md`）都报错。

与最初的设计不同的地方（已改进上面的设计）：

- **资源与操作的定义没有分到各模块**，是 `internal/core` 的一张表（`core.Definitions()`）。
- **归档（冷热分层）并进了 `orders`**（`orders/archive.go`）：数据类别读订单、订单的历史列表在订单的列表里，分开两个包会互相引用。
- **共用的放在 `core`、`documents`、`masterdata`、`ledger`**；`core` 里有组件 ID、依赖 ID、事件类型、错误原因、审计与发件表的写法、记录类型。
- 订单表不是“只经属主写”：订单行同时是台账，交货、出账、确认各在订单行锁下写自己的列（与原来一样，只是写明了；L1b 把台账收进了 `ledger`）。

考试（一个只许读 `AGENTS.md` 与 `docs/` 的子代理，六道找代码的题：改取价、取消时加通知、交货列表加筛选、取消中的订单拒绝认领、部门移动、只跑交货的测试）：六道都找对了文件、函数与测试；它指出七处要猜的地方，已改：认领的“订单不可出账”守卫没写（补进 `docs/flows/delivery-and-billing.md` 与模块说明）、“通知意图”指什么（本组件不通知人，订阅订单事件）、交货列表的字段在哪声明、`make test` 两处说法、取价顺序哪几步在哪个函数、各步不是子测试、`docs/design.md` 的交货表缺列。

顺带发现：集成测试没有覆盖草稿订单的取消、出账来源对未确认或取消中的订单答 `order_not_billable`（L1b-1 补上）；`Makefile` 的 `test-integration` 原来是 `./sales/`，测试搬走后一个集成测试也不跑（本版改成 `./itest/`）；`docs/design.md`、`docs/rules/pricing.md` 里指向旧文件的地方一并改了。

## L4 的结果（2026-11-07）

| 组件 | 版本 | 模块（共用的在后） | 集成测试 | 断言 | 这个组件特有的 |
| --- | --- | --- | --- | --- | --- |
| `mdm/currency` | 3.0.29 | `currencies`、`rates`、`source`；`core` | 拆成 5 步 | 83 | |
| `mdm/partner` | 3.0.33 | `partners`、`roles`、`source`；`core` | 7 步 | 54 | |
| `mdm/product` | 3.0.32 | `products`、`categories`、`units`、`source`；`core` | 8 步 | 58 | |
| `erp/credit` | 3.0.29 | `limits`、`branches`、`masterdata`；`core` | 8 步 | 65 | 只做 L1；分支的生命周期留给 L1b（SF01、SF02） |
| `mdm/org` | 3.0.30 | `entities`、`units`、`tightening`、`replay`、`source`；`core` | 11 步 | 124 | 证据模块叫 `tightening`，不与 SDK 的 `evidence` 同名（SF20） |
| `infra/audit` | 3.0.34 | `intake`、`chain`、`evidence`、`reading`、`archive`；`core` | 端到端拆 6 步，另两个测试照旧 | 176 | 组件定义从 `audit.go` 拆出；读取模块叫 `reading`；没有 `Makefile`（SF09） |
| `erp/inventory` | 3.0.29 | `warehouses`、`stock`、`movements`、`numbering`、`branches`、`issue`、`masterdata`；`core` | 10 步 | 97 | `stock.Key` 的字面量改成带字段名（SF23） |
| `erp/billing` | 3.0.38 | `invoices`、`issue`、`print`、`recoverycheck`、`masterdata`；`core` | 步骤分 6 个文件 | 122 | 更正的路由从入口的闭包挪进 `invoices`（SF19）；打印测试的辅助各包一份（SF22） |
| `infra/iam-casdoor` | 3.0.39 | `login`、`sessions`、`accounts`、`reconcile`、`replay`；`core`，下面 `provider`、`keys` | 按模块分文件 | 289 | `core.Base` 带着 Casdoor 客户端与密钥环，所以这两个包在 `core` 之下（SF08）；存储的方法跟着类型进 `core`（SF21）；`Version` 在 `core`（SF10） |
| `infra/authz` | 3.0.42 | `effectpoint`、`view`、`definitions`、`plans`、`accounts`、`claim`、`restore`、`adminrecovery`、`confirmroutes`；`core` | 原来就是 24 步的端到端加 5 个独立测试，按流程分文件，写索引 | 953（测试函数 34） | 见下 |

`infra/authz` 的取舍：

- 36 个文件几乎彼此全连（SF05）。生效点（变更、事实、决策、写入、确认、冷静期、处置与解除、身份侧处置、待恢复、闭包、预算、再下放）是同一套记录状态与同一张决策表，处置与解除是生效点计划（`Plan`）的一部分、入口又按种类调它们，所以合成一个包 `effectpoint`（17 个业务文件，说明里分组）；其余按“谁调生效点”分：`view`、`definitions`（不依赖生效点）、`plans`、`accounts`、`claim`、`restore`（整套恢复的 6.3 与 6.4–6.5）、`adminrecovery`、`confirmroutes`。分层：`confirmroutes`、`adminrecovery` → `plans`、`accounts`、`claim`、`restore`、`view` → `effectpoint` → `definitions`、`core`。
- 两处依赖反过来：生效点迁移记录后原来直接调计划的 `followRecord`，改成经 `Base.RecordMoved`（入口接到 `plans.FollowRecord`）；确认路由原来在生效点里按种类调计划与账号的确认，单独成 `confirmroutes`。
- 只在一处用的名字跟着模块（`plans` 的作业名与默认值、`claim` 与再下放的默认值、`restore.RecoveryTool`），被几处用的进 `core`（名字、注册表、状态修订、`UUIDText`、`ReplayFacts`）。
- 顺带修了：`Makefile` 补 `test`、`test-integration`；合并安全的测试扩到 `internal/`（SF24：分层以来各组件都只查入口包，放一个违规的探针验证过会红）；集成测试文件里过时的运行命令（`./member/`）。
- 考试（L2 定的“一道窄题前后各考一次”，2026-11-07）：题是“把所有者确认的放宽的冷静期（固定 24 小时）改成配置键 `AUTHZ_COOLING_OFF`：改哪里、值怎样传、测在哪、要谁决定什么”，标准答案 G1–G7 考前写好（`layout-tools/analysis/authz-exam-truth.md`）；两个新会话，一个读 3.0.41（平铺），一个读 3.0.42（分层），都可以读全部、要求找全，只读不改。

  | | 3.0.41（平铺） | 3.0.42（分层） |
  | --- | --- | --- |
  | G1–G7 | 7 条全中 | 7 条全中 |
  | 标准答案以外找到的 | CP108 的路径（`confirm.go` 的 `othersAvailable` 也用这个窗口）；另外三个集成测试写死“25 小时前”；A94、A127 两条决定；`Duration.String()` 传给 `interval` 遇到亚秒的值会出错 | 同左四条，另有：安全 06、09b 把这类参数定为受控的 profile、不产生配置键（做成环境变量键与之冲突）；冷静期与确认的有效期（72 小时）互相约束（见下）；列全 `OthersAvailable` 的四个调用方 |
  | 读的文件 | 约 18（另 grep 片段） | 约 19（另 grep 片段；自动带上 4 份目录说明） |
  | 工具调用 | 16 | 17 |
  | token | 约 10.9 万 | 约 12.4 万 |
  | 时长 | 约 2.3 分钟 | 约 2.7 分钟 |

  结论与 `erp/sales` 的 L1b 考试相同：被要求找全的模型读平铺的代码也找得全，分层没有让读的文件或 token 变少；分层版多找出的两条更深（profile 的既定方向、与确认有效期的约束），但一次考试分不清是结构的功劳还是这一次的运气。分层的收益仍在“先读说明就知道从哪里开始”（分层版直接从 `internal/effectpoint/cooling.go` 开始、读到了 `core.Base` 与入口的接线）与检查拦住的东西上。
- 考试顺带发现、已读代码核实（2026-11-07，不是缺陷）：冷静期满时，待生效的放宽作为到点的作业再进生效点，`confirmationsOf` 只取 `expires_at > now()` 的确认。所有者的确认默认到期在确认后 72 小时（冷静期 24 小时，够用）；他自己签了更早的到期时间、冷静期满时已过期的，按决策表第 23 行回到待确认、保存记录、不按旧确认生效（安全 08 第 188 行），重新确认后不再进冷静期（`cooling_off_until` 已记下，`facts.go` 只在它为空时判断）。安全 08 第 116 行“声明了未来生效时间的记录，确认的有效期从生效时间起算”说的是请求声明的生效时间，冷静期推迟的不在其中。只有冷静期将来做成可配置、且不短于确认的有效期时，才会每一次都这样，那时要一起定（考试里的另一条：安全 06、09b 把这类参数定为受控的 profile）。

## L1b：让规则集中、冲突自己暴露（维护者 2026-11-07 批准）

> 起因：维护者问“这一版能不能很好地理解业务、未来来新需求时能不能快速看出业务之间的冲突”，并说可以重写部分代码、用设计模式，多写代码没关系，怕的是维护成本高、需求互相冲突。L1 只解决了“找得到”：订单状态的判断与写入约 20 处散在 7 个文件里，订单行台账 9 处 SQL 在 3 个模块里直接写，“取消中不交货、不认领”在 3 处各查一遍（出账那处既没写进规则、也没测）；设计文档的订单状态表里第 72 行与第 74 行互相矛盾（过程 `cancelled` 后订单是 `draft` 还是 `cancelled`），没人发现。
>
> 依据：kb 01.03 DDD 的 D5（有要一起保持的不变量的部分用聚合把规则集中一处，不让规则散在各个 Service 里）；kb 10.02 业务逻辑安全（状态只经带前置状态的条件更新改变；状态 × 动作的全矩阵测试）；kb 01.04 的 D5（边界靠检查）。模式只用在订单的生命周期与台账，价格表、列表之类照旧过程式。

`erp/sales` 3.0.40（在 3.0.39 之上，同一个分支）。对外行为不变：路由、事件、错误的原因与文字、审计都照旧，测试锁住。

| # | 任务 | 验收 | 状态 |
| --- | --- | --- | --- |
| L1b-0 | **基线考试**：一个新会话可以读全部代码与文档，回答“订单冻结”这个假想需求要改哪些地方、和哪些规则冲突、要业务决定什么；标准答案先写好（G1–G20，会话临时目录的 `hold-ground-truth.md`），按它评分 | 有分数、有用的工具调用数 | ✅ 见下“基线的结果” |
| L1b-1 | **补测试缺口**：草稿订单的取消；对未确认、取消中的订单认领答 `order_not_billable`；取消中的订单拒绝交货（若没测） | 新测试在旧代码上通过（锁住现有行为） | ✅ `itest/lifecycle_integration_test.go`（步 `lifecycle`）：草稿取消两次、已取消的不能改不能确认、草稿不能交货不能认领、已完成的不能取消交货认领、有交货的不能取消、取消过程进行中不能交货不能认领且再取消不起第二个过程；在 3.0.39 的代码上第一次跑就全过，拒绝的文字逐字相同 |
| L1b-2 | **订单的生命周期一张表**（`internal/orders/lifecycle.go`）：阶段（`draft`、`confirming`、`confirmed`、`cancelling`＝已确认且取消过程进行中、`completed`、`cancelled`）× 命令（修改、提交确认、取消、交货、认领、完成、三种确认结果、取消结束）→ 允许或拒绝（原文的拒绝文字）、结果状态、经过程还是本地、附加条件、审计与否、规则编号 SO-xx；`Decide` 查表；`Transition` 是订单状态唯一的写入（带前置状态的条件更新、发订单事件、按表审计）；全部调用方改成查表，`confirmations.OpenCancel` 并进阶段的计算 | 全矩阵单元测试：每个阶段 × 每个命令都有一格；单元与集成测试全过 | ✅ `b585e1e`：表 6 阶段 × 10 命令，`Decide`、`PhaseOf`、`Transition`；`SetOrderState` 与确认中那条单独的写入、`confirmations.OpenCancel` 都并进表；删一格、加一个阶段，全矩阵测试都红 |
| L1b-3 | **台账只有一个主人**：订单行的台账列（已交货、可出账、认领中、已出账）只经 `internal/ledger` 的五个函数改（认领、退还、正式出账、交货过账、服务确认），每个函数改完在同一事务里发台账事件；事件的先后与现在相同 | 集成测试全过；发件表里事件的顺序不变 | ✅ `ac5179b`：`Claim`、`GiveBack`、`Bill`、`Deliver`、`ServiceConfirmed`；新旧代码各跑一遍集成测试，按请求比较发件表的事件序列，44 组完全相同 |
| L1b-4 | **规则目录与文档对表**：`docs/design.md` 的订单状态表改成与代码同一张表（每格带 SO 编号），修掉第 72 行的矛盾；规则目录（SO 编号 → 代码 → 测试）；单元测试解析设计文档里的这张表，与代码的表逐格比较 | 改一格文档或代码，测试红 | ✅ `11d657a`：文档的表与规则目录 SO01–SO15，修掉第 72 行的矛盾；改文档一格、改代码一格、删测试里的一个编号，三次都红 |
| L1b-5 | **守卫写成检查**（`sales/structure_test.go`，按类型检查，不靠文本猜）：`internal/orders` 以外不比较订单状态、不写 `sales_order.state`；`internal/ledger` 以外不写台账列；订单状态出现在别处 SQL 的读条件里的，必须在检查的清单里登记（文件、用途；新增状态时照这张清单逐一决定） | 每条检查各改坏一次都报错 | ✅ `e049974`、`93bef78`：只有 `lifecycle.go` 不登记；Go 与 SQL 的读者登记到函数（列表的两处、归档、历史列表、台账交给出账、恢复核对）；在 `orders.go` 与 `delivery.go` 各改坏四种，全部报错 |
| L1b-6 | **说明与考试**：各层 `AGENTS.md` 写“订单状态与台账的规则只在这两处”与“加状态或命令时怎样做”；用同一道题在新代码上再考一次（新会话、同样可读全部），与基线比较 | 改造后：找全的程度不低于基线；读的文件与用的 token 明显少于基线；另做一次“只实现、不分析”的检查：在表里加一个状态而不填它的格，全矩阵测试与文档对表测试必须红；结果写在这里 | ✅ `3fa0ebc`：各层说明；考试结果见下“改造后的结果”——找全的程度与基线相同，读的文件没有明显变少（这一条验收没达到） |

### 基线的结果（L1b-0，2026-11-07）

新会话可读 3.0.39 的全部代码与文档，被要求“务必找全”：读了约 32 个文件，21 次工具调用，约 17 万 token，约 2.8 分钟。标准答案 G1–G20 中 19 条答全，G19（确认中暂停撞上参与方 5 分钟的暂存期限）只答到“推进挡不住”；还多找出标准答案没有的：`sales_order.state` 的数据库 CHECK、归档的数据类别要登记新列、“hold”一词在本组件已有两个意思（归档的法律保全、参与方的预占）、`Ledger` 把新状态值发给 `erp/billing`。

结论：一个被要求找全的模型读平铺的 6 千行已经找得全，所以 L1b 的收益不按“找得更全”量，按三件事量：分析的代价（读一张表，不读 32 个文件）；实现的人没做这番分析时由测试拦住；文档与代码不再矛盾（第 72 行那种）。验收照此改（见 L1b-6）。

### 改造后的结果（L1b-6，2026-11-07）

同一道题、同样可读全部（快照 `3fa0ebc`，还没有收紧到 `lifecycle.go` 的那一版检查）：读了约 31 个文件。下表的工具调用、token 与时长取系统的计数（考生自报的调用次数偏少：改造后自报 16，系统记 22）。标准答案 G1–G20 的覆盖与基线相同（19 条全中，G19 半中）。

| | 基线（3.0.39） | 改造后 |
| --- | --- | --- |
| G1–G20 | 19 全 + 1 半 | 19 全 + 1 半 |
| 读的文件 | 约 32 | 约 31 |
| 工具调用 | 21 | 22 |
| token | 约 16.6 万 | 约 16.3 万 |
| 时长 | 约 2.8 分钟 | 约 3.1 分钟 |

- **没达到的**：“读的文件与 token 明显少”：两者都与基线持平。冻结这个需求本身牵动契约、迁移、种子、归档与 `erp/billing`，表省不掉读它们；能被要求“找全”的模型，读平铺的代码也找得全。
- **新出现的**（只有表逼得出来）：表的“一格一个结果”表达不了“回到暂停前的状态”，要定新的效果或拆成两个阶段；某格误写成“忽略”时取消结束后订单静默停住；事务外的 `StoredPhase` 对新状态必须是拒绝；认领的幂等重放先于生命周期检查。
- **机械的保证**（与考试无关、已验证）：加一个阶段而不定它的格，`TestTheLifecycleDecidesEveryCell` 红；文档与代码不一致，`TestTheDesignDocumentIsTheLifecycle` 红；在表以外比较或写订单状态、在 `ledger` 以外写台账、在别处新读订单状态而不登记，`sales/structure_test.go` 红。也就是：做实现的会话没做这番分析时，测试替它拦住。

结论：L1b 的收益在“没分析时也拦得住”与“文档和代码不再矛盾”，不在“分析更快”。

### L1b 的铺开（`erp/credit`、`erp/inventory`、`erp/billing`、`infra/authz`）

照 `erp/sales` 的 L1b 做（生命周期一张表、不变量一个主人、文档对表、结构检查、补测试缺口），每个组件在 L1 之后另起一版。顺序调整的原因：信用组件读下来，分支的生命周期有“一格多个结果”的地方，要先定新的阶段才能写成表——
- `Hold` 新建分支时用一条 `INSERT` 加一条连带十来列的 `UPDATE` 直接写状态（预占或拒绝）；
- `Confirm` 遇到暂存已过期时结果是“到期”而不是“确认”（考虑加阶段“暂存已过期”，像订单的“取消中”）；
- `Consume` 消耗完时才变“已消耗”，没消耗完也照样升版本、发事件（考虑两个命令：消耗、消耗完）；
- 额度占用 `order_exposure` 在预占、释放、消耗三处直接写，要收进 `limits` 的几个函数，并比对发件表事件的先后与版本号不变。
这一类设计值得专门做，不和机械的分层混在一起。

#### 顺序（2026-11-07，AI 定）

先 `erp/billing`（账单的生命周期只在组件内，与 `erp/sales` 同型），再 `erp/credit` 与 `erp/inventory`（两者的分支是协议 04 参与方的同一台状态机，SF03：要不要把参与方的生命周期表放进 SDK——SDK 不得有规范之外的行为，要先在 be-protocol 写规范与向量，再写 Go 的实现、两个组件改用它；这一步单独设计），最后 `infra/authz`（决策表 `core.Decide` 已经是一张表，看记录状态的写入是不是都经 `Transition`、处置与解除能不能做成向生效点登记的种类，SF05）。不再做“前后考试”：`erp/sales` 与 `infra/authz` 两次都表明分层或集中不会让找全的读量变少，收益在检查拦住的东西上（见上）。

#### `erp/credit` 与 `erp/inventory` 的 L1b（SF01–SF03）

维护者 2026-11-07 定：参与方的状态机进 SDK。计划在 [reserve-participant-plan.md](reserve-participant-plan.md)（R0–R6），2026-11-07 做完：be-protocol 第 16 章（alpha.115–116）、be-sdk-go alpha.117 的 `reserve`、`erp/credit` 与 `erp/inventory` 3.0.32 改用它（新旧代码的事件序列相同），全系统换到 alpha.117；SF01–SF03 已修。

#### `infra/authz` 的 L1b（SF05）

2026-11-07 做完，3.0.44：决策表本来就是一张（`core.Decide`，安全 08 的 30 行，逐行测试）；状态的写入本来也只有 `Transition` 一处，但它不核对迁移。先在 `Transition` 里临时记下集成测试的每次迁移（25 种），再照安全 08 的“状态迁移”与“结果对记录状态的作用”写成表（`internal/effectpoint/lifecycle.go`，带暂停原因与结束原因），`Transition` 与新记录的插入按它核对，表外的报错；设计文档同一张表，单元测试逐行比较，那 25 种都在表里；`authz/structure_test.go` 守住唯一的写入与登记的插入（探针各红一次）。生效点不再拆包（AI 定，待复核，理由在结构问题 SF05）。外壳 `be/go-infra` 3.0.69。

#### `erp/billing` 的 L1b（SF04）

账单的状态（`draft`、`confirmed`、`issued`、`void`）与开具后的正式化（`pending`、`done`）：判断在 `invoices`（修改、作废）、`issue`（确认认领、编号、正式化、继续作业）、`print`（只打已开具的）、`recoverycheck`（读）；写入在 `invoices.SetVoid`、`issue` 的三条 `UPDATE`。设计文档的状态表只列允许的迁移，拒绝与重复（已开具的作废、已作废的再作废、非已开具的打印、作废的再开具）只在代码里。

| # | 任务 | 验收 | 状态 |
| --- | --- | --- | --- |
| B1 | **补测试缺口**：生命周期里业务流程走不到的格（各状态上的修改、作废、开具、打印、继续作业）在集成测试里各有一步，锁住现在的回答（含拒绝的原文） | 新测试在当前代码上第一次就过 | ✅ `itest/lifecycle_integration_test.go`（步 `lifecycle`，排在最后）：已确认、已开具（正式化未完成与已完成）、作废的账单拒绝修改；已确认的作废并释放认领；已开具的不能作废；再作废答作废的账单；只有已开具的打印；在 3.0.39 的代码上第一次跑就全过，拒绝的原文逐字相同 |
| B2 | **账单的生命周期一张表**（`internal/invoices/lifecycle.go`）：阶段（`draft`、`confirmed`、`issued`＝已编号、正式化未完成、`formalized`＝已编号且正式化完成、`void`）× 命令（修改、作废、开具请求、认领确认、认领到期、编号、正式化、打印、继续作业）→ 拒绝（原文）、忽略、照做、变成；`Decide`、`PhaseOf`；`Transition` 是 `invoice.state`、`formalization` 唯一的写入（带前置状态的条件更新，事件与审计照旧）；全部调用方改成查表 | 全矩阵单元测试；单元与集成测试全过；发件表的事件序列与改之前相同 | ✅ 5 阶段 × 9 命令，`Decide`、`PhaseOf`、`PhaseOfStored`、`Transition`；作废后的释放、确认后的继续、编号后的事实与正式化工作项留在调用方、同一事务；全矩阵与“已开具与作废的不回头”两个单元测试；新旧代码各跑一遍集成测试（旧代码配上 B1 的新步骤），发件表与审计的 69 行序列完全相同 |
| B3 | **文档对表**：`docs/design.md` 的状态表改成与代码同一张表（每格带规则编号 BL-xx），单元测试逐格比较；规则目录的每个编号都有测试写明 | 改文档一格、改代码一格、删一个编号，各红一次 | ✅ 设计文档“账单的状态”与规则目录 IN01–IN09；改文档一格、改代码一格、删一格、两处测试都去掉一个编号，各红一次 |
| B4 | **结构检查**（`billing/structure_test.go`，照 `erp/sales`）：`lifecycle.go` 以外不比较账单状态、不写 `invoice.state` 与 `formalization`；别处 SQL 读账单状态的登记到函数 | 每条各改坏一次都红 | ✅ `billing/structure_test.go`：表以外写 `state` 或 `formalization`、在 Go 里读 `core.Invoice` 的这两个字段、SQL 的条件读它们而没登记、登记了却不再读，四种改坏各红一次；登记的只有恢复核对的 `ClaimsCheck`（它按阶段算应有的认领，改用 `invoices.PhaseOfStored`） |
| B5 | **说明**：各层 `AGENTS.md` 写“账单的状态只在这里”与“加状态或命令时怎样做”；版本发布 | `make layout-check`、`brickkit lint`、发布 | ✅ 各层说明；`erp/billing` 3.0.40、外壳 `be/go-core` 3.0.67 已发布；结构问题 SF04 移到“已修” |

### 铺开期间的版本

每个组件分层后照常发布；**外壳 `be/go-core`、`be/go-infra` 与依赖方的钉版本在 L4 全部做完后统一换一次**（L4b，不为每个组件各发一次外壳）。所以到 L4b 之前 `make pin-check` 只会因为“依赖方或外壳钉着分层之前的版本”而红。依赖方（`erp/sales`、`erp/credit`、`erp/inventory`、`erp/billing` 对主数据与彼此的依赖）也在 L4b 统一换（原来写 `erp/billing` 对 `erp/sales` 的依赖在它分层的那一版换；之后主数据组件也都发了新版本，统一到末尾一次做）。

## 全局约束

- **只改结构，不改行为**：每个组件的重排是一次单独的版本，不夹带行为的修改；测试锁住旧行为（kb D7 的“迁移与改行为不放在同一次变更里”）。发现的缺陷记进结构问题登记（`docs/zh/01-conventions/12-structure-findings.md`），另起版本修；测试、检查与构建上的缺口（`Makefile`、合并安全的范围）可以同版修。
- 版本：动手前升最后一位；契约（`contract/`）、路由、事件、表一概不变，所以依赖方不受影响。
- 每个组件的提交与发布照常（英文提交信息、`brickkit release --notes-file` 的中文说明）。
- 长任务（全部组件的集成测试、真机格）放后台配监视。

## 完成标准

- 已重建的组件都按新结构，`make layout-check` 进了 `make gates` 并通过；
- 规范、改动配方、组件样板与之一致；
- 真机格全过；
- A160–A163 记进台账；走不通的尝试留下的分支、临时文件清理掉。
