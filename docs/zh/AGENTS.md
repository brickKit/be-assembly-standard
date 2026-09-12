# BrickEnterprise · AI 助手导读

> 这一页是**索引与禁令**，不是教程。它每次会话都会被加载，所以刻意保持薄。
> 细节在它指向的地方——**每一条指向都带节号，别猜**。
>
> 写给 AI 助手，人也能读。**给人看的入口是 [`docs/README.md`](../README.md)**——它按读者分诊（部署人员 / 开发者 / 架构 / 客户），别让人直接从这一页进来。

> ⚠️ **文档语言 ≠对话语言。** 本仓库的规范文档以英文为主（见 [`01-documentation-standard.md`](standards/01-documentation-standard.md) §6），纯粹是为了让 AI 读得更快——这跟"该怎么跟这个项目的人类维护者说话"是两回事：**对方只用中文交流，在这个项目里，不管正在讨论的文件是什么语言写的，回复对方一律必须用中文。** 不要因为这份文件本身是英文，就被带偏去用英文回复。
>
> **这条真的出过错不止一次，而且"发消息前自查一次"这道防线本身已经证明不可靠**：即使这条指令就写在当次会话已加载的这份文件里、就紧邻在用户消息之前，在做完一大段高密度英文的工具输出（翻译文档、改英文文件名、跑处理英文内容的 grep、校验链接的脚本）之后，回复依然整段用英文写出过，不止一次。这说明问题不是"忘记规则"，而是"写完之后再检查语言"这个动作，跟"用什么语言生成正文"本身是同一个失败点——指望在生成过程内部再插一次自查靠不住。**唯一可能生效的做法是把语言锁定为动笔前的默认值，而不是写完后的复查项**：面向用户的正文，落笔第一个字之前就该锚定成中文，不管紧邻的工具调用或文件内容是什么语言，"当前任务域是英文"绝不能成为回复语言的默认锚点。

**这是什么**：基于 brickKit 平台的企业级组件化 ERP/CRM 军火库。62 个组件、5 个外壳、一套按需装配的方法论。本仓库（`be-assembly-standard`）既是标准装配模板，也是**军火库索引**——`components/` 下每个组件是一个 git submodule。

---

## 只有一处必须先读

**§1.5 两条不可让渡的开发原则。** 全书其余部分都可以改，这两条不能：

1. **每个组件都以纯 brickKit 组件形态开发，并独立跑通。** gRPC 一个不省；`extraPorts` 里声明的端口必须真的 `Listen`；能只装这一个组件（连同强依赖树）就 `brickkit up` 起来。
   **「反正最后要合并进外壳，同进程直接调函数不就完了」——这么想一次，K8s 全拆就永远到不了。** gRPC 是逻辑边界的物理载体，省掉它等于合并那一刻边界消失。
2. **合并只发生在部署形态上。** 外壳能做的只有一件事：把 N 个进程变成 1 个进程。

---

## 当前状态

| 项 | 值 |
|---|---|
| 阶段 | **阶段一** ✅ 已出档。**阶段二** ✅ 已出档（[`02-阶段二`](../plans/02-阶段二-验平台.md)，复盘见 [`02-阶段二复盘`](../retrospectives/02-阶段二-验平台-复盘.md)）。**阶段三 · 业务闭环** ✅ 主线已收官——9 个新组件 + 2 个新 SDK，Task 1–15 全部完成；逐 Task 的实现细节、真机验证过程、意外发现的 bug 全部在 [`03-阶段三`](../plans/03-阶段三-业务闭环.md) 本身，这里不重复。核心成果：阶段二 5 个组件的权限判定从 fail-closed stub 换成 `infra-authz` 真实 bundle；全系统第一次有真实签发方（`infra-iam-casdoor`）签发验签通过的 JWT；附录 E"商机赢单→订单→库存→应收"全链路真机跑通。⚠️ **已知的流程偏离**：按 [`02-阶段二复盘`](../retrospectives/02-阶段二-验平台-复盘.md) 定下的规矩，阶段三主线收官后应该先写 `docs/retrospectives/03-阶段三-业务闭环-复盘.md` 再继续（见 [`03-阶段三`](../plans/03-阶段三-业务闭环.md) 的"出档之后要做的事"），但下面三条后续工作是在没有先写复盘的情况下直接开始的——这份复盘目前**仍未补**，找时间应该补上。**阶段三主线之后的三条工作线**（均已完成）：① 测试体系扩展，已固化进 [`04-testing-standard.md`](standards/04-testing-standard.md)；② 种子数据丰富度整改，9 个组件 + 1 个下游同步已按新版本发布（当前版本见下方「已建组件一览」），过程中的具体 bug 见 [`field-tested-pitfalls-log.md`](../dev/field-tested-pitfalls-log.md)（C16–C24、E3）；③ 文档架构重构，规则见 [`01-documentation-standard.md`](standards/01-documentation-standard.md)，本项工作本身进行中。 |
| 已建组件 | **14 个建完**，见下方「已建组件一览」表。十三个后端组件的 `iamJwksUrl`/`authzBundleUrl` 都指向真实运行的对端。 |
| 工具仓库 | `be-sdk-go@v0.2.5`、`be-ops@v0.1.5`、`be-acceptance@v0.3.8`（`make gates` 六个 gate 的产出方）、`be-sdk-python@v0.3.1`、`be-sdk-ts@v0.3.3`——全部已 tag（带注解）并被装配仓库的 submodule 指针跟踪。⚠️ **已知的版本漂移**：`be-sdk-go@v0.2.5` 修的 `StartOutboxPump` 原子认领 bug（踩坑记录 C15）目前只有 `infra-iam-casdoor`/`erp-inventory`/`erp-sales` 升级到位，其余业务组件仍在更早的 v0.2.1-v0.2.4——这个 bug 只在 K8s 多副本场景触发，不是本阶段的阻塞项，按"下次改动顺带升"处理。每个工具版本具体修了什么、哪次真机验证发现的，见各自仓库自己的 changelog 或 [`field-tested-pitfalls-log.md`](../dev/field-tested-pitfalls-log.md)（C11/C12/C15、A9/A10/A11、类别 F）。 |
| 已钉死不许改的 | `registry/ports.tsv`、`registry/schemas.tsv`、`registry/permissions.tsv`（**只增不改**，见下）；**每种语言的技术栈与模块入口签名**（设计书 §12.4 / §12.5）；**PC 端骨架形态**（§12.6.7）；**权限体系**（第 14 章） |
| 平台 CLI | 已装 **v0.2.2**。`brickkit restore`（含 `--check`）、`init --hooks`、`sync`/`remove` 对已登记 submodule 的守卫（`SUBMODULE_GUARD`）均已实现并在用。已知修复历史见 [`field-tested-pitfalls-log.md`](../dev/field-tested-pitfalls-log.md) 与 brickKit 仓库自己的 changelog。 |
| 常用验收 | `make tier0`（档 0 六项验收，**每加一个组件都要重跑**）、`make docs-check REPO=<仓库名>`、`make gates`、`make version-check`（扫全部 submodule 的 tag 漂移） |

⚠️ **改了阶段就回来改这张表。** 它是 AI 判断「现在该做什么、什么已经定死」的唯一依据。**这张表只放现在为真的事实**——历史叙事（发生过什么、为什么）不属于这里，属于上面链到的那些文档（见 [`01-documentation-standard.md`](standards/01-documentation-standard.md) §2.1）。

### 已建组件一览

| 组件 | 版本 | 定位 | 详细设计 |
|---|---|---|---|
| `mdm-customer` | 1.0.5 | 只读枢纽，`data_scopes: none` | [`docs/design/mdm-customer.md`](../design/mdm-customer.md) |
| `mdm-product` | 1.0.6 | 只读枢纽，`data_scopes: none` | [`docs/design/mdm-product.md`](../design/mdm-product.md) |
| `erp-inventory` | 1.0.13 | 物理命令枢纽：TCC 三件套 + claim-first 幂等 + `warehouse` 维数据权限 | [`docs/design/erp-inventory.md`](../design/erp-inventory.md) |
| `erp-finance` | 1.0.9 | 事件汇枢纽：`FinanceService` 11 rpc + `legal_entity` 维数据权限 | [`docs/design/erp-finance.md`](../design/erp-finance.md) |
| `erp-sales` | 1.0.18 | 唯一的链上一环：四条强依赖全部真实 gRPC 调用，`ConfirmOrder` 的 TCC 补偿链 + `org`/`owner` 两维数据权限 | [`docs/design/erp-sales.md`](../design/erp-sales.md) |
| `infra-authz` | 1.0.4 | 权限体系里唯一持久化状态的组件：`GET /authz/bundle` 策略下发，纯并集无 Deny | [`docs/design/infra-authz.md`](../design/infra-authz.md) |
| `infra-iam-casdoor` | 1.0.6 | `slot:iam` Default 成员：两个 token 架构，refresh token rotation + 重放检测 | [`docs/design/infra-iam-casdoor.md`](../design/infra-iam-casdoor.md) |
| `infra-workflow` | 1.0.2 | 零依赖审批待办中心：claim-first 幂等 + `owner`/`org` 两维数据权限 | [`docs/design/infra-workflow.md`](../design/infra-workflow.md) |
| `infra-notification` | 1.0.3 | 路由中枢：零依赖零出边完全活在事件图上，两层通道偏好 | [`docs/design/infra-notification.md`](../design/infra-notification.md) |
| `integration-im-dingtalk` | 1.0.4 | `channel:im` 族第一个成员：钉钉 access_token 缓存刷新 | [`docs/design/integration-im-dingtalk.md`](../design/integration-im-dingtalk.md) |
| `infra-print` | 1.0.4 | 全系统第一个 Python 组件：纯函数打印渲染中心，PDF/ZPL 双渲染 | [`docs/design/infra-print.md`](../design/infra-print.md) |
| `infra-bff-mobile` | 1.0.12 | 全系统第一个 TypeScript 组件：GraphQL BFF，零强依赖零数据库 | [`docs/design/infra-bff-mobile.md`](../design/infra-bff-mobile.md) |
| `frontend-standard` | 1.0.0 | PC 独立 Vite SPA + 移动端 Uni-app H5，唯一没有后端形态的组件 | [`docs/design/frontend-standard.md`](../design/frontend-standard.md) |
| `crm-opportunity` | 1.0.7 | 阶段三第一个业务组件、CRM 域第一个组件：商机全生命周期 | [`docs/design/crm-opportunity.md`](../design/crm-opportunity.md) |

⚠️ **版本号 changelog 的唯一源头是每个组件自己的 `component.yaml`**——这张表只给"现在是什么版本、这个组件是干什么的"，不复述版本历史。想知道某个组件从建仓库到现在经历了什么，去读它自己的 `component.yaml` 或 `git log`。

---

## 路由表：要做 X，读 Y

| 你要做的事 | 先读 |
|---|---|
| 搞清整体理念、九域、三枢纽、四把尺子 | 设计书 §1、§2.5、§2.6 |
| 起环境 / 查基础资源 | 总纲 §1；`make help` |
| **刚起完 14 个组件，想要点数据直接测/演示，不想从零建客户产品** | `make seed-data`（[`docs/dev/种子数据一览.md`](../dev/种子数据一览.md)）——真实建出多角色测试账号 + 客户/产品/库存/订单/商机/财务凭证/打印模板，仅供本地用；`make seed-data-clean` 撤销能清的部分 |
| **有人问「怎么装 / 怎么部署 / 数据库谁建」** | [`docs/ops/部署手册.md`](../ops/部署手册.md)。⚠️ **别把设计书或总纲甩给部署人员**——那份手册是自足的，需要看别处时它自己会指路。数据库分五层、只有第 3/4 层要人动手，见它的 §3 |
| **写代码/配置时“看起来对、静态检查也过、一跑起来才发现不对”** | [`docs/dev/field-tested-pitfalls-log.md`](../dev/field-tested-pitfalls-log.md)——可能已经踩过。**只记这一类坑**（第三方镜像的实际行为、Docker/Compose 的行为、脚本自己的逻辑漏洞），设计决策不放这里 |
| **写任何 `component.yaml`** | 总纲 §2.1 端口册 + §2.2 schema 册 + 全局约束 B/C/E/F。**端口不许自定** |
| **开始写代码**（任何组件） | 总纲 §4 **SOP-W** —— 七步循环、测试分四层、红绿节奏、一次会话装多少。**这是驱动其余 SOP 的节奏，先读它** |
| **选框架 / 建后端骨架 / 写 `main`** | 总纲 **全局约束 §K** + 设计书 **§12.4**（技术栈逐格锁定表）+ **§12.5**（模块入口契约）。**框架不许自选**：Go = Gin，Python = FastAPI，栈的其余每一格同样定死 |
| **配置怎么读 / 日志与 OTel 怎么初始化 / 指标注册到哪** | 设计书 **§12.5.2 / §12.5.3** + 总纲 SOP-L 的 **L-1/L-2**。一律从 `rt` 拿，**模块代码里零 `os.Getenv`**、零进程级 init |
| 写一个新组件 | 总纲 §4 SOP-D（四份文档）→ SOP-R（查参考）→ SOP-B（后端）/ SOP-F（前端） |
| **测试该写在哪一层 / 怎么测 / 卡住了怎么办**（任何测试相关问题都先查这里） | [`docs/standards/04-testing-standard.md`](standards/04-testing-standard.md)——**测试的唯一真相源**：L1-L4 分层判据（判据是「把实现删掉用另一种语言重写，这条测试还该成立吗」）、红绿节奏、卡住时的三条出路（⚠️ **绝不许注掉测试 / 加 `t.Skip` / 放宽断言**）、三种运行粒度、跨组件测试、扩展范畴、前端测试分层，全在这一份 |
| **种子数据/测试数据该怎么设计、组件间数据怎么协作**（依赖组件没有需要的数据形态时该怎么办） | [`docs/standards/05-data-construction-standard.md`](standards/05-data-construction-standard.md)——**数据的唯一真相源**：两条数据路径的定义与物理隔离、种子数据的丰富度判据与归属协作原则、跨组件缺数据时"先补齐依赖组件"这条判据，全在这一份，跟测试标准是两份独立的文档 |
| **想真跑某个组件的跨组件 L4 测试**（平时 `make test` 里被 `t.Skip` 掉的那些） | `make test-cross REPO=<仓库名>`——只跑这一个组件，强依赖 gRPC 指向真实在跑的依赖容器（要求强依赖树在跑）。详见 [`04-testing-standard.md`](standards/04-testing-standard.md) §四 |
| 写前端 | 总纲 §4 **SOP-F**（十六条前端铁律）；设计书 **§12.6**（UI 层逐格锁定：AntDV + vxe-table / wot-design-uni / ECharts）、**§12.6.7**（PC 骨架 = AWS Console 式两级导航）、**§12.6.8**（偏好三层归属）、§12.6.5（视觉方向）、§5.9、§12.2 |
| **前端测试该写在哪一层 / E2E 什么时候补** | [`docs/standards/04-testing-standard.md`](standards/04-testing-standard.md) §六：FE-1（单元）/FE-2（组件）已在用，FE-3（E2E）/FE-4（视觉回归）明确推迟到前端功能开发完再统一做，骨架已定；跟 §7.1（三种运行粒度）是同一套框架 |
| **加一个接口 / 判「谁能调它」** | 设计书 **第 14 章 §14.1**。权限键写在 `assembly.yaml` 的 `permissions` 段；注册用 `besdk.GET(r, path, permKey, h)`——**漏写权限键编译不过**；判定是进程内 map 查找，**组件里没有权限表** |
| **让某张表「只让某些人看到某些行」** | 设计书 **第 14 章 §14.2**。⚠️ **`assembly.yaml` 的 `data_scopes` 段必填**，不需要也要写 `data_scopes: none`（省略 = `be-ops` 报错）。条件静态写进 `.sql` 传参，**不用 RLS**；`org` 维走 `dept_path` 前缀匹配，**不需要组织树副本** |
| 改契约 | 设计书 §3.4 铁律 3、§8.5；组件仓库 `make contract-check`（`.proto` 破坏性变更）+ 根 `make gates` 的 `events-breaking-scan`（`events/*.json` 破坏性变更）。**只增不删不改**——删字段/改类型/删 subject 一律报红 |
| 加迁移 / 分区表 | 设计书 §11.2；**§11.2.3 迁移状态表必须落各自 schema** |
| 事件 / Outbox / 幂等 / 补偿 | 设计书 §3.10、§4.4、§4.5、§4.6 |
| 合并部署 / 外壳 | 设计书 §13；`shells/*/AGENTS.md` |
| 装配生成（路由表、建库脚本、端口册、权限键册…） | 总纲 §2.4 `be-ops` 的 11 个产出 |
| 验收 / 门禁 | 设计书 §3.11、§9.6.2、§13.7；`make gates` |
| **一个阶段计划做完了，下一个还没开工** | 先写 `docs/retrospectives/0X-阶段N-<名>-复盘.md`——问题/矛盾/brickKit 理念问题/流程改进/是否要重排阶段，参照 [`02-阶段二复盘`](../retrospectives/02-阶段二-验平台-复盘.md) 的结构 |
| **不知道某段业务逻辑该怎么写** | 三步法（先自己设计，卡住了才查参考）见 [`02-reference-implementation-standard.md`](standards/02-reference-implementation-standard.md) §1；**该看现实中哪个开源 ERP 的哪个模块**是本项目专属的，总纲 §4 SOP-R 的 R-2 表。**先读那个模块，再回来实现** |
| **拿不准要不要用设计模式** | [`03-ai-development-standard.md`](standards/03-ai-development-standard.md) §1：判据按**你（AI）能不能快速看懂**来定；§1.1 有「帮 AI / 害 AI」两张表 |
| **发现同一功能有多种实现、每一种都合理** | [`02-reference-implementation-standard.md`](standards/02-reference-implementation-standard.md) §4：那是**新槽位族的信号**，不是「做成可配置」。先回设计书新增族（§5.11.1、决策 104），**严禁在一个组件里写 `if costingMethod ==`** |
| **要不要为某个功能新建一个仓库** | 总纲 §3.5.1 那张表（8 个非组件仓库 + 各自的创建时机）+ §3.5 的三步话术。⚠️ **判据只有一条：现在有没有已经写好、正等着 push 的文件。** 没有就不建 |
| 某个具体组件 | `docs/design/<仓库名>.md`（为什么这样设计，含第 8 节参考实现）+ `components/<scope>/<name>/AGENTS.md`（怎么改它） |
| 平台 CLI 的行为 | `.claude/skills/` 下四个技能；brickKit 仓库 `design/` 下 14 本 |
| **文档该怎么组织、什么时候该拆成独立文件、组件文档要同时服务哪两种读者** | [`docs/standards/01-documentation-standard.md`](standards/01-documentation-standard.md) |

**这张表没覆盖到？** 查全部 `docs/standards/*.md` 文件——它们是一个封闭集合，永远有效的规范文档全在里面（见 [`01-documentation-standard.md`](standards/01-documentation-standard.md) §2.4/§7）。

**冲突时的优先级**：设计书 > 总纲 > 阶段计划 > 本页。发现下层与上层矛盾，**改下层**。

---

## 二十三条最容易写错的（每条都带症状）

前六条与第 11、12、15、16、17、19、21、23 条的共同点：**代码看起来完全正确，测试也能过**，症状要么极难联想，要么根本没有。

19–23 是权限体系（设计书第 14 章）带来的。**第 21 条是全项目第三条「悄悄读到别人数据」的路径**——前两条是第 2 条（`SET` 不带 `LOCAL`）与第 16 条（模块里 `os.Getenv`）。

11–15（含 13b）是**照着 brickKit 的实际代码核对出来的**，其中 11、12、13 三条直接推翻了设计书旧版的说法。

**16、17、18 三条只在合并进外壳之后才错**——单独跑那个组件 100% 正确、测试全绿、`make smoke` 也过。它们由 `make module-check`（门禁 9）守。

| # | 不许 | 症状 | 出处 |
|---|---|---|---|
| 1 | `grpc.Dial(os.Getenv("X_GRPC_ENDPOINT"))` | 平台注入的值**恒为 `http://` 开头**，没有 `grpc://`。连不上，而**报错指向名称解析**，极难联想到是这里。必须 `TrimPrefix("http://")` | §2.1 |
| 2 | 不带 `LOCAL` 的 `SET ROLE` / `SET search_path` | 连接还回共享池后**下一个借用者原样继承**——A 组件的查询打在 B 组件的表上，**不报错、不崩，只是悄悄读写了别人的数据**。全项目最难查的一个 | 决策 3、§13.3 铁律二 |
| 3 | 组件之间互相 `import` | **没有任何症状**，系统跑得更快了，直到要上 K8s 全拆才发现拆不动，代价是重写。也不许抽「公共 model 包」 | §13.3 铁律六、决策 91 |
| 4 | `os.environ["X_ENDPOINT"]` / `os.Getenv` 后判空当缺失 | 弱依赖缺失时那个变量**根本不存在**（不是空串），下标访问启动即崩。这是平台刻意的设计 | §3.6 |
| 5 | 往 `component.yaml` 写 `asset` / `assembly_role` / `slot_name` / `edge_routes` / `menus` / `domain` / `tier` / `shell` | 未知键**当场报错**，不是静默忽略。这些全部放同目录 `assembly.yaml` | §3.5、决策 84 |
| 6 | 配置项起名 `otelEndpoint` / `databaseSchema` | 命中平台保留后缀 `*_ENDPOINT` / 前缀 `DATABASE_`，被**跳过并只给一条警告**——组件拿不到值，而 `up` 一路绿灯。必须叫 `otelBaseUrl` / `pgSchema` | §2.7.3 |
| 7 | `/healthz` 里查库、查依赖组件、查 NATS | 一个下游抖动让所有上游同时被判不健康并重启；合并态下**一个模块拖挂探针，整组 22 个组件一起重启** | §12.3.6 |
| 8 | `FROM scratch` / `distroless` 基底 | 平台的健康检查是 `CMD-SHELL`，没 shell 就永远失败。症状是**组件日志写着「已就绪」，而平台说它不健康**。基底必须带 `/bin/sh` + `wget` | §12.3.7 |
| 9 | Docker labels / K8s annotations 的值写成 `true` / `8080` | 两边都只收字符串，平台**不做自动转换**，`traefik.enable: true` 会被当场拦下。一律带引号 | §5.10 生成器铁律一 |
| 10 | 客户没买的组件写 `enabled: false` | 它下面那一串**跟着级联不启动**——关掉 hrm 顺带把 mdm 关了。「没买」的正确写法是**整条不写进 `brickkit.yaml`** | 决策 98、§9.5 |
| 11 | 以为「换基础资源实现只改 `brickkit.yaml` 一个字段」 | `engine` **逐字参与匹配**：组件写 `nats` 而项目写 `kafka`，`up` 直接阻断。换事件总线要改 ~50 份 `component.yaml` **加**换 SDK driver（客户端库不同）。对象存储反而真零改动——**`engine` 写能力名 `s3`**（默认实现 RustFS，换 MinIO/S3/OSS 零改动）。判据：**协议兼容写能力名，协议不兼容写产品名**（后者让平台在换实现时主动阻断，因为那本来就是一次迁移） | 设计书 §2.7.3.1、决策 105 |
| 12 | 对 `STORAGE_ENDPOINT` 也 `TrimPrefix("http://")` | 它是**唯一一个名字带 `ENDPOINT`、值却是裸 `host:port`** 的变量（组件地址走 `http://` 拼接，资源 storage 走 `host:port`）。剥它等于什么都没剥，然后把裸 `host:port` 交给要 URL 的 S3 SDK。基础库里这两个必须是**两个方向相反的函数** | 设计书 §2.1、决策 105 |
| 13 | 给平台生成的容器挂 Traefik 路由 `labels` | **平台生成的 compose 自建一个非 external 的 bridge 网络，`brickkit.yaml` 里没有字段能改。** Traefik 的 Docker Provider 只看得见同网络的容器，所以那些 labels 它**一条都读不到**。症状：**labels 写对了、`docker inspect` 看得见，而网关 404、容器全 healthy**。正确做法是 `expose: true` + `exposePort` + Traefik **file provider** | 设计书 §6.3.1、决策 107 |
| 13b | 在 `labels` 里写 `app` / `brickkit.io/*` / `com.docker.compose.*` | 这三组归平台所有，**写了当场报错**（不是静默丢弃）。我们要产出的 `prometheus.io/*` 与 `traefik.http.*` 安全 | 设计书 §5.10 |
| 14 | 给带外容器分配 `1xxxx` 段端口 | `1xxxx` 整段归平台：它给 `local: true` 组件做宿主机映射时首选 `10000 + 容器端口`、fallback 从 `18080` 起递增。带外容器一律走 `2xxxx` | 总纲 §1.2、决策 106 |
| 15 | 照着某个开源 ERP 的模块结构直接搬一遍 | **没有立刻的症状**，但会把它的通病一起搬进来——最典型的是「所有模块同进程同库、可跨表 JOIN」，而那正是本项目存在的理由（设计书 §1.1）。它们同进程同库，我们独立进程独立 schema，**结构不可能相同** | 总纲 §4 SOP-R |

| 16 | 在模块代码里 `os.Getenv` / `os.environ` 读配置 | 一个进程只有一份 `environ`：合并后 22 个模块的 `PG_SCHEMA` 与**每份 `configSchema` 里的每一项**互相顶掉——**不报错**，模块按别人的 schema 建表、读写数据。这是「悄悄读写别人的数据」的第二条路径（第 2 条是第一条）。依赖地址走 `besdk.Endpoint()`，其余配置**全部走 `rt.Config`** | 设计书 §12.5.3、决策 110 |
| 17 | 模块自己 `otel.SetTracerProvider` / `logging.basicConfig` / 装信号处理器 / 用**默认** Prometheus registry / 调 **`gin.SetMode()`**（它是**包级变量**，不是 engine 字段——一个模块设 debug，另外 22 个模块一起进 debug，panic 堆栈吐给客户端） | 前两个**最后一个 init 的赢**——22 个模块的 trace 全挂在同一个 `service.name` 上、日志格式被某个模块顶掉，而**一路全绿**；第三个让 `docker stop` 关不干净；第四个**直接崩**（Go `MustRegister` panic / Python `Duplicated timeseries`），而单跑时 100% 正常。全部从 `rt` 拿 | 设计书 §12.5.2、决策 110 |
| 18 | 模块里 `log.Fatal` / `os.Exit` / `sys.exit`；或自己 `gin.New()` / `sql.Open()` / `Listen` | 一个模块启动时踩到一个**可恢复**的错，**整组 22 个组件一起没了**。自己 `gin.New()` 会漏掉 SDK 那一串中间件——不报错，只是这个组件从此没有 trace、没有 RED 指标。一律返回 error，engine 用 `besdk.NewGinEngine(rt)`，池用 `rt.DB`，端口由调用方 `Listen` | 设计书 §12.5、§13.3 铁律七、决策 109 |
| 19 | 改 `registry/permissions.tsv` 里**已发布**的键名 | 所有已分配该权限的角色**当场静默失权**，不报错。症状是「客户升级后某几个人突然点不动某个按钮」。废弃走 `deprecated` 墓碑列，**键名永不回收** | 设计书 §14.1.2 |
| 20 | 前端只判了 `features` 没判 `permissions` | **菜单看得见、点进去整页 403。** `features` 是**装配级**（这个环境装了没有），`permissions` 是**用户级**（这个人能不能）——设计书旧版把两者混着说 | §14.1.8 |
| 21 | 用户请求路径上用 `besdk.SystemClient` | **数据权限整条被绕过，不报错，返回的数据只是「多了一些」。** 这是第三条「悄悄读到别人数据」的路径。`SystemClient` 只许出现在 `Start()` 与事件 handler 里，`make gates` 扫 | §14.2.6 |
| 22 | 省略 `assembly.yaml` 的 `data_scopes` 段 | 被 `be-ops` 当场拦下——**这是刻意的**。「省略」不等于「不需要」，不需要必须显式写 `data_scopes: none`。安全机制的默认值只能 fail-closed | §14.2.2 |
| 23 | 把 authz 的可达性写进 `/healthz`；或业务代码裸用 `gin.Engine` 的 `GET/POST` | 前者让 authz 一抖动**整组 22 个模块一起重启**；后者绕开了权限键的签名强制，**那个接口从此无人鉴权且完全没有症状** | §12.3.6 / §14.1.7 |

⚠️ **第 15 条的正确做法见 [`02-reference-implementation-standard.md`](standards/02-reference-implementation-standard.md) §1 的三步法**：先自己设计一版，卡住的地方才查参考，然后回来自己想清楚再写——绝不照抄。许可证方面的说明（借鉴逻辑不构成衍生作品，要避免的只是逐行照抄源码）也在该文档里。

另外两条金额与查询的：**金额字段一律 `string` 传 decimal**（`double` 跨语言丢精度）；**List 不给 `offset` 字段**，深分页在契约层面就不可表达（决策 53）。

---

## 四张钉死的表：只增不改

| 表 | 为什么不许改 |
|---|---|
| `registry/ports.tsv` | **gRPC 等额外端口没有任何事后补救手段**：平台改写地址时明确跳过额外端口，两个 `local: true` 组件撞同一额外端口时 `brickkit up` 生成阶段硬报错。写到第 30 个组件才发现要回头改前 29 份 Manifest（§3.5.1.1） |
| `registry/schemas.tsv` | 库一旦按「一组件一 database」建好、数据进去了，再改成一库多 schema 就是一次数据迁移（决策 3） |
| `registry/permissions.tsv` | 权限键是**跨版本的持久标识**：改一个已发布的键名，所有已分配它的角色**静默失权且不报错**。由 `be-ops` 产出 9 从各组件 `assembly.yaml` 聚合，废弃走 `deprecated` 墓碑列，键名永不回收（第 14 章 §14.1.2） |
| `.gitmodules` | 它就是设计书 §3.4.1 要的「组件 → 仓库 → 精确 commit」映射表，是半年后接手的人**唯一**能查到「这个客户的 `erp/sales@1.0.0` 到底是哪一份代码」的地方 |

唯一的端口复用例外：`slot:frontend` 族 4 个前端组件共用 80（槽位互斥、永不共存、各自独立 Nginx 容器不进外壳）。

---

## 仓库结构与三条运维禁令

```
components/<scope>/<name>/   每个组件一个 git submodule（scope/name 是组件 ID，仓库名是扁平的 domain-name）
components/.archived/        brickkit sync 的归档区（以 . 开头，文件管理器默认隐藏）
shells/{go,python}/          外壳，不是组件，不进 brickkit.yaml
tools/{be-ops,be-acceptance,be-sdk-go,be-sdk-python,be-sdk-ts}/
registry/                    端口册 + schema 册
docs/standards/               长期有效的规范文档，按阅读优先级编号 00-05（00-总纲最先读；其余按组件真实开工流程排列——文档/参考实现/AI开发/测试/数据构建标准）
docs/plans/                   每阶段一份的执行计划（历史记录，不是规范）
docs/design/                 组件设计计划，一个组件一份
docs/zh/                     上面英文正本的中文镜像（路径与仓库根一一对应，见 01-documentation-standard.md §6/§7）
```

| 禁令 | 为什么 |
|---|---|
| **`brickkit remove` 前必须先 commit & push** | 它**连同已归档的源码目录一起删除**。submodule 里有未 push 的改动时这是数据丢失（§9.4.2） |
| **提交前跑 `make arsenal-restore`** | `brickkit sync` 整目录搬家会在本仓库的 diff 里留下「整棵树搬家」。pre-commit hook 会拦，但先跑一次省事（总纲 §3.3） |
| **Fork 件的 `metadata.id` 与 `version` 一个字都不能改** | 改了之后所有依赖方拿到的 `*_ENDPOINT` **整个消失**——平台注入的变量名是从组件 ID 推导的，整条 Fork 机制当场垮掉（§3.4.1） |
| **`brickkit sync`/`remove` 遇到已登记为 submodule 的组件会阻断，不会自动帮你搬/删** | v0.2.0 曾经用纯文件系统操作（`os.Rename`/`os.RemoveAll`）静默搬删，会打断 `.gitmodules` 且不报错（已反馈并在 v0.2.1 修复，见 brickKit 仓库 `docs/superpowers/specs/2026-09-06-submodule-tracked-components-gap-report.md`）。**现在**遇到这种情况会报 `SUBMODULE_GUARD` 错误并打印等价的手工命令（`git mv` / `git submodule deinit` + `git rm`），照着做完再重跑一次即可——这是预期行为，不是 bug |

**找不到源码时先看 `components/.archived/`。**

---

## 常用命令

```bash
make help                        # 所有目标
make check                       # 一键查询基础资源（容器/镜像 tag/端口/健康/网络）
make up                          # 一键开启默认资源（先整体预检，不符则一个都不动）
make <res>-up / <res>-down       # 单个可选资源：minio/keycloak/kafka/rabbitmq/nginx/obs
make registry-check              # 端口册与 schema 册自洽
make gates                       # 铁律六 import 扫描 + SystemClient 误用 + 裸路由 + 事件契约破坏性变更 + 数据权限边界测试缺失
make docs-check REPO=<仓库名>     # 某个组件的四份文档结构检查
make test-cross REPO=<仓库名>     # 局部跑一个组件的跨组件 L4 测试（强依赖树要在跑）
make test-db-init                # 建/刷新本地测试库 brickkit_test_db（跟演示库 brickkit_db 物理分开，见下方"测试库与演示库分开"）
make arsenal-check / -restore    # 军火库结构与 brickkit.yaml 是否自洽
brickkit up --dry-run            # 只算不启动，看这次会跑哪些、什么顺序
brickkit down                    # 停掉 14 个组装态容器（不删 volume）——见下方"容器默认关闭"
```

**任何 `brickkit` 命令的参数去问 `brickkit <命令> --help`。** 本页与 `.claude/skills/` 都刻意不复刻参数清单——复刻一份就是承诺维护两份，而过期的那份会让你自信地敲出一条 `unknown flag`。

⚠️ **组装态的 14 个组件容器默认应该是关着的，不是常年挂着。** `make up` 管的 `be-postgres`/`be-nats`/`be-casdoor` 等**基础资源**是长期开发基础设施，可以一直开着；但 `brickkit up` 拉起来的 14 个组件容器只在**真机验证/演示**时才需要，用完就 `brickkit down`（不删数据）。长期挂着有两个真实代价：① 忘了重新 `brickkit up` 就成了跑着旧版本的容器（真实踩过：`infra-notification` 挂着 `v1.0.0` 时代码早改到 `v1.0.2` 都没人发现）；② 同机真实容器会跟本地测试的临时 NATS 订阅者抢同一个 subject 的消息，断言结果不确定（踩坑记录类别 E 的 E1/E2）——容器不在跑，这类问题从根上就不存在，不需要靠"测试用私有 subject"这种防御性写法兜底。

⚠️ **测试库与演示库物理分开：`TEST_PG_DSN` 指向 `brickkit_test_db`，不是 `brickkit_db`。** 同一个 `be-postgres` 实例里两个物理分开的 database，`make test-db-init` 建/刷新测试库那一份。完整原因（为什么不能共用）见 [`docs/standards/05-data-construction-standard.md`](standards/05-data-construction-standard.md) 的 §一。

---

## 平台的四条铁律（brickKit 侧）

1. **版本必须精确。** `1.2.0` 可以，`^1.2` / `~1.2` / `1.2.x` / `latest` 一律不行。范围版本是**被论证过后拒绝**的，不是还没做。
2. **不许碰保留变量。** `COMPONENT_ID`、`COMPONENT_VERSION`、任何以 `_ENDPOINT` 结尾的、以及 `DATABASE_` / `REDIS_` / `MQ_` / `STORAGE_` / `SEARCH_` / `SMTP_` 开头的，由平台注入；`configSchema` 里起同名项会被跳过。
3. **健康检查有禁令。** 别把依赖的可用性写进自己的健康检查。**默认启动宽限是 60 秒**（不是 30）；Python 写 `120`、Node 写 `90`、Go 不写、外壳镜像写 `300`。
4. **启停跟着上层走。** 顶层关掉，下面那一串跟着不启动。收窄范围唯一的路是改 `brickkit.yaml` 的 `enabled`，**没有 `--only` 之类的参数**。

> 第 3 条的「60 秒」修正自 `brickkit init` v0.1.1 生成的旧版导读（那份写的是 30 秒）。依据是设计书 §12.3.5：平台的 `startPeriodSeconds` 默认值就是 60，`interval`/`timeout`/`retries` 写死为 10s/3s/3。**平台导读的权威版本在 brickKit 仓库**；本页接管了这个文件，所以 `brickkit skills update` 不会再刷新它（`.claude/skills/` 下那四个技能仍会正常刷新）。

---

## 不要提议的东西（都是被论证过后拒绝的）

| 别提议 | 理由 |
|---|---|
| 把 `make seed` 建的测试账号/角色（比如 `dev.superuser`）写进 migration，图省事让容器一启动就有 | Migration 每次部署都会跑，**包括真实客户的生产部署**——写进去等于给每一个客户的系统永久埋一个密码公开、权限覆盖一切的后门账号，跟"生产 Casdoor 应用不许开 `password` 授权类型"是同一类风险。真实部署"第一个管理员怎么来"这个鸡生蛋问题已经有安全的答案：`infra-authz` 的 `bootstrapAdminSub` 配置项 + `Start()` 里的 `EnsureBootstrapAdmin`，让真实部署方填真实的 `sub`，不需要硬编码账号。测试账号只能留在 `make seed`（手动触发，从不出现在部署/CI 流程里）；通用的产品基线数据（默认仓库、默认法人+科目表这类，不含身份凭据）继续放 migration，两者不是一回事 |
| 给 brickKit 加注册中心 / 配置中心 / 网关 / 常驻服务 | 平台刻意极简。**正因为它克制，我们才能只改 DNS 指向就把对端换成任何东西** |
| 引入 Redis | JWT 无状态 + 本地摘要副本 + PG 行级锁 + 网关限流已覆盖它的全部常见用途（决策 71）。**权限也不需要它**：判定是进程内 map 查找（决策 116），在中间加一跳 Redis 只会更慢 |
| 给各组件建「角色→权限」副本表 + 事件同步；或让组件每请求去问 authz | 决策 116：前者把一个 map 查找做成了分布式缓存失效问题（62 张表 + 62 条依赖边）；后者是每请求一次网络调用（决策 16 反对）。正解是 **OPA 式本地 PDP**：`GET /authz/bundle` 每 15s 条件拉进**进程内存 map**，**组件里零表零迁移零事件**（第 14 章 §14.1.4） |
| 把权限键塞进 JWT | 决策 116：普通用户没事，**超级管理员的全集会顶爆 8KB header——症状是登录成功、随后所有请求 431**。JWT 只带身份（`sub`/`roles[]`/`dept_path`/`org_id`），权限键一个都不进（§14.1.5） |
| 给权限加「显式拒绝（Deny）」 | 决策 116：**K8s RBAC 明确不做 Deny**，理由就是可推理性；AWS 的 Deny/Allow 求值顺序正是它难用的主因。纯并集下「他为什么能看到这个」永远只有一个答案。「除了 X 都能做」的正解是给他一个不含 X 的角色 |
| 给数据权限做一个运行时可配的管理界面 | 决策 118：**数据权限随版本上线**（同 SAP / Odoo / PG RLS）。唯一运行时可改的 Salesforce，代价是一张物化 Sharing Table，**改一条规则大组织要后台重算几小时**——那是物化视图重算问题。而「制度级」的东西定死在代码里还顺带可 diff、可回滚 |
| 用 PostgreSQL RLS 做数据权限；或造一个通用的「记录共享」引擎 | 决策 118：`sqlc` 拼不动动态 WHERE 是个**错误前提**——条件静态写进 `.sql` 传参即可，前提一垮 RLS 就不划算（它还带着「**表 owner 默认 bypass RLS**，policy 写了却一条都没过滤」这个静默陷阱）。至于共享引擎：那是在造 Zanzibar，而**实例级需求（把这个客户转给另一个销售）是业务功能**，改 `owner_id` 就完了（§14.2.1） |
| 引入 Consul / etcd / Zookeeper | 路由表生成期聚合，不需要运行时服务发现（决策 72） |
| 把事件总线 / 对象存储包成组件 | 我们零代码的东西不该包成组件——包了之后「换实现」从改一个字段变成改几十个 Manifest（决策 86） |
| 让网关或可观测性当组件 | 平台的资源 `kind` 是封闭清单（无 `gateway` / `iam` / `telemetry`），且 Manifest **没有 volumes 字段**，配置文件挂不进去 |
| 前端用 React | 决策 79：ToB 表单双向绑定、多端统一、AI 生成代码结构清晰、国内生态。锁定 Vue3 + Uni-app |
| PC 端换 Element Plus / Naive UI；或想「统一两端的组件库」 | 决策 111：PC 锁 **AntDV v4 + vxe-table**，移动端 **wot-design-uni**。**两端不同是设计使然**——移动端是卡片列表/扫码/两个审批按钮，PC 是密集表格/多级联动长表单，共用组件的收益接近零（AntDV 依赖 DOM 只是顺便封死这条路）。两端唯一共享的是 `packages/design-tokens`：**共享 token，不共享组件** |
| 在业务页面里直接 `import` 第三方 UI 组件（含 `<vxe-grid>`） | 决策 111：第三方只许出现在 `packages/ui-kit-pc` / `ui-kit-mobile`，对外暴露我们自己的组件名。与 `be-sdk-*` 同一个道理——换实现改一个文件，而不是改 40 个页面。表格尤其要紧：**vxe 是「默认选择，待核」**（部分能力属于商业版），页面一律用 `<BeTable>`，逃生口每个都要在 `ui-kit-pc/README.md` 记一行（§12.6.6） |
| 为了「更好看」再混一个 UI 库进来 | 决策 111：混搭的**唯一**理由是 AntDV 确实没有这个能力（甘特图、审批流设计器、富文本、代码编辑器、大屏）。**两个库的 token 体系对不齐，混得越多越不好看**；而真正毁观感的是「这一页间距 16、下一页 20」（§12.6.5） |
| 把 vue-vben-admin / antdv-pro 当依赖引进来做骨架 | 决策 112：它的路由+权限层由「后端菜单表 / 静态路由 + 角色码」驱动，我们是 `/api/tenant/features` 的 feature-flag 驱动——换掉那一层就只剩一个 layout，而依赖树全留着。**读它的 layout / router+access / request 三块，不装它**（SOP-R 的 R-2） |
| PC 端做成左侧多级树（域 → 组件 → 页面三层展开） | 决策 113：菜单是 62 份 `assembly.yaml` **生成期聚合**来的，没有中心菜单表可以重排；而**每个客户装的组件不同，那棵树家家形状不同**，AI 生成页面时不知道它落在哪一层。骨架锁定为 **AWS Console 式两级导航**（服务选择器 + 收藏栏 + 服务内扁平菜单 + 应用内标签页 + ⌘K + 组织/法人切换器，§12.6.7） |
| 照抄 AWS Console，连「没有应用内标签页」一起抄 | 决策 113：AWS 的页面基本无表单状态，刷新没损失；**ERP 一张未保存的出库单，浏览器一刷就没了**。金蝶 / 用友 / SAP Fiori 全都是应用内标签页。另两处必改：服务内菜单强制扁平、Region 切换器换成组织/法人切换器 |
| 业务页面从空白 `<div>` 开始摆布局 | 决策 113：AWS Console 最被诟病的就是**视觉不统一**（每个服务团队各做各的），而**我们的病因一模一样——62 个组件的页面由 AI 分批生成**。一律从 `ui-kit-pc` 的页面级模板起手：`<BeListPage>` / `<BeDetailPage>` / `<BeFormPage>` / `<BeSettingsPage>` |
| 给用户一个「布局模式」切换器，或照 admin 模板抄三十项偏好 | 决策 114：真实客户没人切，而它让 62 个组件的页面要在三种布局下各测一遍。归用户的只有四项——**收藏的组件、亮/暗、密度、语言**（+ 表格列态，纯本地）。主色 / logo / 水印 / 灰度是**装配期配置**（§12.6.8） |
| 把 `packages/design-tokens` 写成 TS 常量导出 | 决策 114：亮/暗与紧凑都要**运行时切 token**，编译进 bundle 的常量在运行时换不了。**必须是运行时可写的 CSS 变量**，且必须在写第一个页面之前定死——**晚了改的是每一个页面**。这是整套前端设计里唯一有时间压力的一条 |
| Go 侧换 Echo / Fiber / chi / 裸 `ServeMux`；或用 GORM | 决策 108：栈逐格锁定。中间件在 `be-sdk-go` 里只写一遍，写第二遍那份必然烂；GORM 要自己管连接与会话，和外壳的单一全局池打架 |
| Python 侧用 Flask / Django；或同步 `grpc`；或 gunicorn 多 worker | 决策 108：**这几条是物理的**。WSGI 的同步 handler 拿不到共享 asyncpg 池；同步 gRPC 要在每个方法里 `run_coroutine_threadsafe` 桥一次；多 worker = 多进程，Outbox 推送线程跑 N 遍，而外壳形态只有一个进程 |
| Python 侧用 alembic 管迁移 | 决策 108：**理由不是「跨语言不统一」**（迁移工具本来就按语言分，Go 用 `golang-migrate`、Python 用 `yoyo-migrations`，因为外壳不跨语言），而是**它对我们没价值**——零 ORM 让 autogenerate 完全用不上，而我们的硬 DDL（`PARTITION BY`、`DETACH CONCURRENTLY`）在 alembic 里只能包在 `op.execute("""…""")` 里，套了一层 `.py` 的壳而壳里什么都没有。**但语言内必须统一**：同一个外壳里两种迁移工具，那个启动器要写两套编排 |
| 把 `main.go` 写成「自己装配一切」（开池、Listen、装信号、init OTel） | 决策 109：那套装配在合并那天全要重写，而 §13.7 的拆回门禁会因此在半年后第一次真跑时全红。`main` 只有一行 `besdk.RunStandalone(module.New)` |
| 用 Java / C# 写组件 | JVM 内存与启动开销和「客户本地单机部署」根本冲突（决策 78） |
| 为了代码生成自研工具链 | 工具优先，AI 兜底。有现成的就用现成的（决策 32） |
| K8s 上做部分合并部署 | `local: true` 只能配 `deploy.target: docker`，K8s 目标下 CLI 生成阶段直接报错。**上 K8s 就是全拆，没有中间态**（决策 88） |

---

## 写代码之前的自查（第 0 条最要紧）

0. **我是不是在为了让测试通过而改测试？** 默认该改的是实现。测试真的写错时**先停下说清哪里错**，改测试要单独一次 commit（[`04-testing-standard.md`](standards/04-testing-standard.md) §2.3）。**L2 业务规则测试挡路时，几乎一定是实现或理解错了。**
1. **我要写的东西，端口和 schema 是从 `registry/` 抄的，还是我自己起的？** 自己起的一律错。
2. **我是不是让两个组件模块直接互相认识了？** 跨组件只能走 gRPC/HTTP + `contracts/`，代码不共享（`be-sdk-*` 是唯一白名单）。
3. **这段代码在「同一个进程里还有另外 22 个模块」的前提下还对吗？** 三个问法：我读了 `os.Getenv` 吗？我初始化了什么进程级的东西（OTel / 日志 / 信号 / 默认 registry）吗？我在什么地方 `log.Fatal` 了吗？三个都是「否」才算过（设计书 §12.5、§13.3 铁律七）。
4. **这段逻辑我是凭空想的，还是走了 SOP-R 的三步法？** 顺序是：自己先设计 → 理不清才去读别人的 → 回来自己写。凭空设计漏掉的边界情形要到客户上线三个月后才暴露；而空着脑袋去读别人的，会把它们的通病一起搬进来。
5. **我是不是在用 `if` 硬扛一个本该是槽位族的分歧？** 如果这几个分支对应的是「不同客户画像各自合理的做法」（成本核算法、拣货策略、审批路由…），那是 [`02-reference-implementation-standard.md`](standards/02-reference-implementation-standard.md) §4 的槽位族信号——该新增一个族，而不是加分支。
6. **这个文件是不是已经太长了？** 一个函数超 150 行、一个文件超 600 行、或一条 `if-elif` 链超 5 个分支且还会长，就对照 [`03-ai-development-standard.md`](standards/03-ai-development-standard.md) §1.2 判一次。判据是**你自己下次新开会话能不能只读两个文件就改对**。反过来，**逻辑本身很简单却硬套模式，是更糟的结果**——多一层间接就是多一个你必须跳转、却什么都没学到的文件。
7. **我改的这处，四份文档里哪几份该跟着改？** 边界/契约/事件变了 → 先改 `docs/design/<仓库名>.md`；功能变了 → README；用法或结构变了 → `docs/手册.md`；禁令或判据变了 → 该仓库的 `AGENTS.md`。**顺序是文档先行，不是代码先行。**
