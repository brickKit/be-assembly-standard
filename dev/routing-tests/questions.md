# AI 路由题库（31 题）

> 开发文件，06d 的考试输入。考法、评分、过关线见 [README.md](README.md)。**考生绝不能看到本文件**：考场副本必须排除 `dev/`。
> 请求原文按请求者的说法写，不照抄文档标题；中英混排（维护者用中文问，外部 AI 可能用英文问）。

## 读题说明

- **期望路径**：按顺序列出；「必经」是评分时检查的，「可选」读了不扣分也不加分。`AGENTS.md` 的 Where to look 行用该行左列的关键词指代；`→` 表示顺着链接或按文档指示走下去。组件文档在 06b 写成，路径先写到"`components/<scope>/<name>/BRICKKIT.md` 的哪一节"，开考前按 README §3 核对。
- **期望结论**：改动题用 `brickkit-plan-change` 的四种结论：Fits one component / Needs a provider's contract first / Needs a new component / Conflicts；非改动题写"直接作答"。**结论按后端组件判**（README §5 结论维度）：前端永远是消费方，不是上游；只有一个后端组件要改、再加前端跟进，仍是 Fits one component（+ 前端跟进）；后端上游必须先于后端消费方改，才是 Needs a provider's contract first。
- **相邻答法给分**：考生答成相邻类别或常见错误路线时结论维度给几分。考生不知道四种结论的名字，阅卷按实质（改哪些组件、什么顺序、停没停）映射，不按用词。
- **禁止**：F0 = `dev/`、`archive/`、`brickkit-feedback/`、`components/.archived/`、`shells/`、brickKit 仓库、依赖方源码、`~/.claude/`（详见 README §2；全仓搜索结果里出现但没有打开的不算，见 README §5 路径维度）。各题另有补充的写在后面。
- **要点**：「必含」决定答案维度得分；「加分」只记录不计分。
- **陷阱**：这道题故意引诱的错误路线。
- **开考前核对**：这道题依赖的前提，06d 开考前逐条确认。

## 题目总览

| 题 | 类别 | 语言 | 期望结论 | 标签 |
|---|---|---|---|---|
| Q01 | 只改一个组件 | 中 | Fits one component（erp/inventory，+ 前端跟进） | |
| Q02 | 只改一个组件 | 英 | Fits one component（erp/sales） | 审批路由 = fork 不是槽位 |
| Q03 | 只改一个组件 | 中 | Fits one component（后端契约不改；frontend/standard，菜单项可能在 erp/finance 的 `assembly.yaml`） | 听着像后端，其实不改后端契约 |
| Q04 | 只改一个组件 | 中 | Fits one component（infra/workflow，+ 前端跟进） | |
| Q05 | 只改一个组件 | 英 | Fits one component（crm/opportunity） | 听着像要改上游，其实上游已有 |
| Q06 | 只改一个组件 | 英 | Fits one component（crm/opportunity，+ 前端跟进） | 引诱共享引擎 |
| Q07 | 需要先改上游 | 中 | Provider first：mdm/customer → erp/sales（erp/finance 不改） | 引诱固定天数或 sales 自己算应收 |
| Q08 | 需要先改上游 | 英 | Provider first：erp/sales → erp/finance | 引诱跨 schema JOIN |
| Q09 | 需要先改上游 | 中 | Provider first：crm/opportunity → erp/sales → erp/finance | CRM–ERP 无同步边 |
| Q10 | 需要先改上游 | 英 | Provider first：erp/inventory → infra/notification | 不对族成员建边 |
| Q11 | 需要先改上游 | 中 | Provider first：mdm/product → erp/inventory（+ 前端跟进） | |
| Q12 | 需要新组件 | 中 | New component：integration/im-feishu | 槽位族（channel:im） |
| Q13 | 需要新组件 | 英 | New component：infra/iam-keycloak | 槽位族（slot:iam）；v1：JWKS 地址是共享变量 |
| Q14 | 需要新组件 | 中 | New component：mdm/supplier、erp/purchase | |
| Q15 | 需要新组件 | 英 | New component：crm/lead | 引诱撑大现有组件 |
| Q16 | 与已有决策冲突 | 中 | Conflicts（0004、0005） | |
| Q17 | 与已有决策冲突 | 英 | Conflicts（0012） | 槽位族 vs 客户 fork |
| Q18 | 与已有决策冲突 | 英 | Conflicts（0001、0022） | |
| Q19 | 与已有决策冲突 | 中 | Conflicts（0008） | 听着像普通后台配置 |
| Q20 | 与已有决策冲突 | 中 | Conflicts（0021） | v1：只拉 bundle 不建边 |
| Q21 | 部署与配置 | 中 | 直接作答 | v1：数据库密码 |
| Q22 | 部署与配置 | 英 | 直接作答 | v1：focus 运行 |
| Q23 | 部署与配置 | 中 | 直接作答 | v1：一个环境一份部署文件 |
| Q24 | 部署与配置 | 英 | 直接作答 | v1：成员服务名，不改组件也不覆盖地址 |
| Q25 | 部署与配置 | 中 | 直接作答 | v1：mode debug 只在 deploy.local.yaml |
| Q26 | 排障 | 英 | 直接作答 | v1：deploy.local.yaml 整份替代 |
| Q27 | 排障 | 中 | 直接作答 | |
| Q28 | 排障 | 英 | 直接作答 | v1：外壳是独立仓库（子模块） |
| Q29 | 外部使用者视角 | 英 | 直接作答（只读 erp/sales 的 BRICKKIT.md） | |
| Q30 | 外部使用者视角 | 中 | 直接作答（只读 im-dingtalk 的 BRICKKIT.md） | |
| Q31 | 外部使用者视角 | 英 | 直接作答（只读 infra/print 的 BRICKKIT.md） | 引诱去读项目决策 |

中文 16 题、英文 15 题。

**非改动题（Q21–Q31）共用的相邻答法给分**：直接作答 → 2；答对但附带一个不必要的"改某组件代码 / 契约"建议 → 1；把问题当成需求开出改组件的计划、或拒绝作答 → 0。各题另有的写在题内。

---

## 一、只改一个组件

### Q01 华东仓的货要挪到华南仓，现在只能先盘亏再入库

- 类别：只改一个组件
- 请求原文（中）：「华东仓有一批货要挪到华南仓。现在只能先在华东做一笔盘亏、再在华南做一笔入库，中间要是有一步失败了账就对不上，而且盘盈盘亏的数字全被搅乱了。能不能直接做个调拨？」
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「a new requirement, a feature, "where should this go"…」→ `.claude/skills/brickkit-plan-change/SKILL.md` §1–§3
  2. 必经：`AGENTS.md` Overview「Three hubs」（erp/inventory 是唯一的实物库存流水写入者）与末尾组件表 → `components/erp/inventory/BRICKKIT.md` — Purpose、Contracts（现有 Receive / Adjust；事件清单里已占位的 `erp.inventory.transferred.v1`）
  3. 必经：`docs/en/01-conventions/02-backend.md#events-and-cross-component-writes`（`idempotency_key` 先原子占位再写）
  4. 必经：`docs/en/01-conventions/02-backend.md#data-scopes`；`docs/en/01-conventions/02-backend.md#permissions` → `docs/en/01-conventions/07-registries.md#permission-keys`
  5. 可选：`components/erp/inventory/AGENTS.md`；`docs/en/01-conventions/06-testing.md#l2-business-rule-tests`（核心交易组件用性质测试）
- 期望结论：Fits one component（erp/inventory），+ 前端跟进（调拨页面 / 按钮）。契约只增：新 rpc / REST 端点，补全已占位事件的字段；minor 版本。
- 相邻答法给分：inventory 先发版、再改前端加调拨入口 → 2（前端跟进不改变结论）；只改 inventory 不提前端 → 2；inventory 为主、但多拉一个不必要的后端上游（如说要先改 mdm/product）→ 1；在前端或 erp/sales 里串两次 Adjust / Receive → 0；新建一个调拨组件 → 0。
- 标准答案要点：
  - 必含：归 erp/inventory——它是唯一写实物库存流水的组件；不新建"调拨组件"，也不让前端或别的组件串两次 Adjust / Receive
  - 必含：一次调拨在**同一个事务**里写一出一进两条流水，要么都成、要么都不成；请求带 `idempotency_key`，用原子的 `INSERT … ON CONFLICT DO NOTHING` 先占位
  - 必含：数据范围按 `warehouse` 维度，调用者对来源仓和目标仓都要有权限，两个都校验
  - 必含：新权限键（如 `erp.inventory.transfer`）声明在 erp/inventory 的 `assembly.yaml` 的 `permissions`，由 `be-ops permissions --root .` 并入 `registry/permissions.tsv`，再刷新 infra/authz 配置的权限目录（漏了这步，对新键的检查全部失败）；路由注册时带上这个键；不改已有键
  - 必含：契约只增；数量是十进制字符串
  - 加分：L2 性质测试（调拨前后两仓合计不变、余额不为负）；不复用 Adjust 的盘盈盘亏原因码，免得污染盘点数据
- 禁止：F0
- 陷阱：听起来像"把两步操作编排起来"，容易引向在前端或 erp/sales 里串两次调用，或新建一个调拨组件。
- 开考前核对：06b 没有实现调拨（若已实现，改成"调拨要支持在途状态"或换题）；erp/inventory 的 `BRICKKIT.md` Contracts 是否写了占位事件。

### Q02 Big orders need a manager's approval before confirmation

- 类别：只改一个组件
- 请求原文（英）："Orders above 100,000 should need a sales manager's approval before anyone can confirm them. Who builds that, and how?"
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「a new requirement…」→ `brickkit-plan-change` SKILL.md
  2. 必经：组件表 → `components/erp/sales/BRICKKIT.md` — Purpose、Dependencies（infra/workflow 是可选依赖）
  3. 必经：`components/infra/workflow/BRICKKIT.md` — Purpose（只收任务、不判业务规则）、Contracts（`CreateTask`、`infra.workflow.task.completed.v1`）
  4. 必经：`docs/en/01-conventions/10-reference-implementations.md#which-project-to-read`（infra/workflow 一行：绝不引入 BPMN 引擎）或 `#slot-family-signal`（Approval routing 一行）
  5. 可选：`docs/en/01-conventions/02-backend.md#events-and-cross-component-writes`；`docs/en/01-conventions/04-configuration.md#key-names`；`docs/en/02-decisions/03-contracts-and-data/0010-money-as-strings-lists-by-cursor.md`
- 期望结论：Fits one component（erp/sales）。infra/workflow 的现有契约已够用，不用改。
- 相邻答法给分：只改 erp/sales（+ 前端展示"待审批"）→ 2；规则在 erp/sales，但另外要求 infra/workflow 先加一个其实不需要的接口 → 1；把阈值 / 审批人规则放进 infra/workflow，或引入 BPMN / 规则引擎 → 0；把审批路由做成可配置开关或槽位族 → 0。
- 标准答案要点：
  - 必含：归 erp/sales：由它判断"要不要审批、谁来审"，通过 infra/workflow 的 `CreateTask` 登记待办，消费 `infra.workflow.task.completed.v1` 得知同意或驳回后再继续或拒绝确认
  - 必含：阈值和审批人规则不放进 infra/workflow（它不判业务规则），不引入 BPMN / 规则引擎
  - 必含：金额按十进制字符串比较，不用浮点
  - 必含：阈值做成 erp/sales 的配置键，大写下划线（如 `APPROVAL_AMOUNT_THRESHOLD`），声明在 `configSchema`，经 `rt.Config` 读取，不读进程环境
  - 必含：infra/workflow 是可选依赖，要说清它没装时怎么办（降级行为由人拍板，不能静默跳过审批而不说）
  - 加分：订单状态机新增"待审批"状态并补 L2 状态迁移测试；事件消费幂等、只接受更大的 `version`；不同客户要不同的审批路由（金额分档、矩阵）→ 客户 fork erp/sales，不是做开关、不是槽位族
- 禁止：F0
- 陷阱：听起来是"工作流功能"，引诱把规则写进 infra/workflow、引入 BPMN 引擎，或把审批路由做成可配置。
- 开考前核对：workflow 的 `BRICKKIT.md` Contracts 列出了 `CreateTask` 和 `task.completed` 事件；erp/sales 仍把 infra/workflow 声明为可选依赖；06b 没有加大额审批。

### Q03 财务想在页面上点一下就关账

- 类别：只改一个组件
- 请求原文（中）：「财务月底想在系统页面上点一下就关账，还有反关账、锁定期间。现在每次都得找开发帮忙调接口。」
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「a new requirement…」→ `brickkit-plan-change` SKILL.md
  2. 必经：组件表 → `components/erp/finance/BRICKKIT.md` — Contracts（期间 close / reopen / lock 的 REST 已存在，权限键 `erp.finance.close`）
  3. 必经：`components/frontend/standard/BRICKKIT.md` — Purpose
  4. 必经：`AGENTS.md` Where to look「a frontend page, the component library…」→ `docs/en/01-conventions/03-frontend.md`（#page-templates、#features-permissions-and-menus、#business-logic-and-data-access、#internationalisation 至少其三）
  5. 可选：`components/frontend/standard/AGENTS.md`；`docs/en/02-decisions/04-frontend/0014-third-party-ui-only-in-ui-kit.md`
- 期望结论：Fits one component。后端契约不改。两种实现都对：(a) 关账入口放在 erp/finance 现有页面或固定在底部的"Component settings"里——只改 frontend/standard；(b) 关账页在 erp/finance 的服务菜单里单独占一项——菜单项声明在 erp/finance 的 `assembly.yaml` 的 `menus`（随 finance 发一版），再前端跟进。
- 相邻答法给分：(a) → 2；(b)，且菜单项放在 erp/finance 的 `assembly.yaml` → 2（不论考生把它叫"先改上游"还是别的，前端跟进不改变结论）；(b) 但把菜单写进前端的手写菜单表 → 1（答案维度另按 0015 扣分）；认为要给 erp/finance 新增关账接口（没核对出接口已有）→ 1；新建组件 → 0。
- 标准答案要点：
  - 必含：后端已有 `POST /periods/{period}/close|reopen|lock`（权限键 `erp.finance.close`），erp/finance 的业务代码和契约不动
  - 必含：页面从 ui-kit 页面模板起（`<BeListPage>` / `<BeSettingsPage>` 等），不从空 `<div>` 起；不在页面里直接 import AntDV / vxe
  - 必含：按钮用 `v-be-auth="'erp.finance.close'"`，菜单 / 路由同时看 features 和 permissions
  - 必含：请求走从契约生成的 API 客户端，不手写 `fetch('/api/…')`；"这个期间能不能关"由后端判定，前端不复制规则
  - 必含：界面文案走 i18n，中英文齐全
  - 加分：锁定不可逆，前端加二次确认；说清菜单项属于 erp/finance 的 `assembly.yaml`，没有中央菜单表
- 禁止：F0
- 陷阱：听起来是财务后端需求，引诱去改 erp/finance 的接口；反过来也可能在页面里写死关账规则。
- 开考前核对：06c 没有做关账页面；finance 的 `BRICKKIT.md` Contracts 列出了这三个 REST 和权限键；06c 定下菜单形态后，若 finance 的菜单已有可容纳关账的页面，期望结论可收紧为 (a)。

### Q04 休假前想把待办转给同事

- 类别：只改一个组件
- 请求原文（中）：「我下周休假，想把手上还没处理的审批待办转给同事，现在系统里做不到。」
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「a new requirement…」→ `brickkit-plan-change` SKILL.md
  2. 必经：组件表 → `components/infra/workflow/BRICKKIT.md` — Purpose、Contracts
  3. 必经：`docs/en/01-conventions/02-backend.md#data-scopes`、`#permissions`
  4. 可选：`docs/en/01-conventions/02-backend.md#contracts`、`#events-and-cross-component-writes`；`docs/en/01-conventions/07-registries.md#permission-keys`；`components/infra/workflow/AGENTS.md`
- 期望结论：Fits one component（infra/workflow），+ 前端跟进（PC 待办页的"转交"按钮）。
- 相邻答法给分：workflow 先发版、再改前端 → 2；workflow，并把"通知新处理人"列为 infra/notification 的后续可选改动 → 2；把 workflow + notification 当成必须一起做（notification 先或同时）→ 1；去 infra/authz 给同事临时角色、做代理 / 共享记录机制 → 0。
- 标准答案要点：
  - 必含：归 infra/workflow——转交是待办箱自身的机制，不是业务规则，业务组件不用改
  - 必含：新增转交操作（rpc + REST），契约只增；带 `idempotency_key`
  - 必含：数据范围：只能转交自己名下的待办（`owner` = `assignee_sub`），或在自己 `org` 范围（`assignee_dept_path` 前缀）内的待办；转交后待办的处理人和部门路径改成新处理人的
  - 必含：权限键要么新增（如 `infra.workflow.task.reassign`，声明在 workflow 的 `assembly.yaml`，`be-ops permissions --root .` 并入 `registry/permissions.tsv`，刷新 infra/authz 的权限目录），要么说明复用 `infra.workflow.task.act` 的理由；不改已有键
  - 加分：发一个只增的新事件（如 `infra.workflow.task.reassigned.v1`），以后 infra/notification 可以订阅去提醒新处理人；在审批历史里记一条转交
- 禁止：F0
- 陷阱：容易想成"代理 / 共享"机制（0009 排除记录共享引擎），或去 infra/authz 给同事临时加角色；也可能把通知新处理人当成必须同时改 infra/notification。
- 开考前核对：06b 没有实现转交。

### Q05 Block new opportunities for disabled customers

- 类别：只改一个组件
- 请求原文（英）："Customers that are DISABLED in master data still show up when reps create an opportunity, and people keep opening new deals for them. Stop that."
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「a new requirement…」→ `brickkit-plan-change` SKILL.md
  2. 必经：组件表 → `components/crm/opportunity/BRICKKIT.md` — Purpose、Dependencies（mdm/customer 是它的依赖）
  3. 必经：`components/mdm/customer/BRICKKIT.md` — Contracts（客户已有状态字段、`Get` / `BatchGet`、`mdm.customer.disabled.v1` 事件）
  4. 必经：`AGENTS.md` Where to look「calling another component; showing data another component owns」→ `docs/en/01-conventions/02-backend.md#calling-other-components`
  5. 可选：`docs/en/02-decisions/01-architecture/0002-one-schema-per-component.md`
- 期望结论：Fits one component（crm/opportunity）。mdm/customer 已经提供了需要的一切。
- 相邻答法给分：只改 crm/opportunity（前端选择器顺手过滤停用客户作为跟进）→ 2；规则在 crm/opportunity，但认为 mdm/customer 要先加一个其实已有的字段或事件 → 1；只在前端过滤 → 0；读 `mdm_customer` 的表 → 0。
- 标准答案要点：
  - 必含：规则在 crm/opportunity 的后端：建商机（以及改客户）时拒绝 `DISABLED` 的客户，返回明确的错误
  - 必含：客户状态通过 mdm/customer 的现有接口拿（`Get` / `BatchGet`，用户请求路径上用 `UserClient` 转发调用者的 token），或用 `mdm.customer.disabled.v1` 维护本地摘要；绝不读 `mdm_customer` 的表
  - 必含：mdm/customer 不用改（状态和事件都已存在）
  - 必含：只在前端过滤掉停用客户不够：隐藏不是约束，后端要拒绝
  - 加分：已经存在的、属于停用客户的未结商机怎么处理（提示 / 不动），交给人决定；L2 测试覆盖"停用客户建商机被拒"
- 禁止：F0
- 陷阱：听起来像要先改主数据（"需要先改上游"），实际上游已经有了；也可能只改前端选择器。
- 开考前核对：mdm/customer 的 `BRICKKIT.md` Contracts 写了状态、`BatchGet` 和 disabled 事件；crm/opportunity 还没有这条校验。

### Q06 Hand a leaving rep's deals to a colleague in one go

- 类别：只改一个组件
- 请求原文（英）："Zhang from sales is leaving. His manager wants to hand all of Zhang's open opportunities to Li in one go, and Li has to be able to see and work on them afterwards."
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「a new requirement…」→ `brickkit-plan-change` SKILL.md
  2. 必经：组件表 → `components/crm/opportunity/BRICKKIT.md` — Purpose、Contracts（`UpdateOpportunity` 已能改 `owner_id`）
  3. 必经：`AGENTS.md` Where to look「making a table show only some rows to some people」→ `docs/en/01-conventions/02-backend.md#data-scopes` → `docs/en/02-decisions/02-permissions/0008-data-scopes-ship-with-the-version.md`（"Sharing one record … change the record's `owner_id`"）
  4. 可选：`docs/en/02-decisions/02-permissions/0009-no-row-level-security.md`
- 期望结论：Fits one component（crm/opportunity），+ 前端跟进（批量转交入口）。
- 相邻答法给分：crm/opportunity 加批量转交端点（+ 前端）→ 2；"单条已能改负责人，逐条改即可，不用改代码"、没有回应"一次全部" → 1；建共享表 / 可见性规则、在 infra/authz 给 Li 加能看张三数据的角色、用 RLS → 0。
- 标准答案要点：
  - 必含：把商机交给另一个人 = 改记录的 `owner_id`（0008 明说这是业务功能），不是共享表、共享引擎（0009）、运行时数据范围规则或 RLS
  - 必含：单条已经能做（`UpdateOpportunity` 带 `owner_id`，权限 `crm.opportunity.edit`，带 `version` 乐观锁）；"一次全部转"需要在 crm/opportunity 新增批量转交端点（契约只增、带幂等键）
  - 必含：经理只能转交他自己数据范围（`org` 前缀 / `owner`）内的商机，批量端点也要按调用者的范围过滤
  - 必含：转交后 Li 能看到，是因为 `owner` 维度现在等于 Li——不需要给 Li 加任何"能看张三的数据"的规则
  - 加分：`dept_id` / `dept_path` 是创建时快照，是否跟着新负责人改，交给人决定；已经由赢单生成的订单仍属于张三，是 erp/sales 那边的另一件事；权限键新增还是复用，要说理由
- 禁止：F0
- 陷阱："Li has to be able to see them" 引诱去做可见性规则、共享记录，或给 Li 一个能看张三数据的角色。
- 开考前核对：crm/opportunity 的 `BRICKKIT.md` Contracts 写明可改负责人；06b 没加批量转交。

---

## 二、需要先改上游

### Q07 按各客户的账期拦截逾期客户的新订单

- 类别：需要先改上游
- 请求原文（中）：「我们给客户的账期不一样，有的月结 30 天，有的 60 天。客户只要有款过了账期还没收回来，就不许再给他确认新订单。现在只看信用额度，拦不住这种情况。」
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「a new requirement…」→ `brickkit-plan-change` SKILL.md（§3、§4：先上游后消费方）
  2. 必经：组件表 → `components/erp/sales/BRICKKIT.md` — Purpose、Dependencies（mdm/customer、erp/finance 都是它的依赖；确认订单时已查信用占用）
  3. 必经：`components/erp/finance/BRICKKIT.md` — Contracts（`ListARLedger` 可按 `customer_id`、`created_before` 查应收行，每行有 `amount`、`reconciled_amount`、`created_at`）
  4. 必经：`components/mdm/customer/BRICKKIT.md` — Purpose、Contracts（客户主数据的字段）
  5. 必经：`docs/en/01-conventions/02-backend.md#contracts` 或 `docs/en/02-decisions/03-contracts-and-data/0011-contracts-are-additive-only.md`
  6. 可选：`docs/en/01-conventions/02-backend.md#calling-other-components`；`docs/en/01-conventions/10-reference-implementations.md#which-project-to-read`（mdm/customer → `res.partner`）
- 期望结论：Needs a provider's contract first：mdm/customer（客户加账期字段，契约只增）→ erp/sales（确认订单时取客户账期，用 erp/finance 现有的 `ListARLedger` 找出过了账期还没核销完的应收，有就拒绝）。erp/finance 不用改。
- 依据（给阅卷人，不给考生）：已对照契约核实——`mdm/customer` 的 `Customer` 只有名称、税号、信用额度、状态、联系人、开票信息，没有账期；`erp/finance` 的 `ARLedgerEntry` 有金额、已核销金额、创建时间，但没有到期日或账期；`erp/sales` 的契约里也没有账期。全项目都没有"账期"这个数据，所以必须有一个上游先加；`ListARLedger` 已能提供应收行，所以 finance 不是必改项。
- 相邻答法给分：
  - mdm/customer → erp/sales（sales 用 `ListARLedger` 的未核销金额 + 创建时间 + 客户账期算逾期）→ 2
  - mdm/customer 先加账期，再由 erp/sales 把账期随 `sales.order.created.v1` 带给 erp/finance、finance 在台账上存到期日并提供逾期查询，最后 erp/sales 调用（账期来源仍是 mdm/customer，顺序对）→ 2
  - 账期只存在 erp/sales 自己（sales 建一张按客户的账期表），再用 `ListARLedger` 计算 → 1（能工作，但客户主数据放错了组件）
  - 只改 erp/sales，用 `ListARLedger` 加一个**统一的**固定天数（配置键）判断、不管各客户账期 → 0（漏掉了"账期各不相同"这个需求本身）
  - 判成 finance 先加逾期查询、sales 再调，但没有任何地方提供账期 → 1（链条形状对，账期来源没解决）
  - 顺序颠倒 → 1
  - erp/sales 读 `erp_finance` 的表，或自己根据订单推算应收 → 0
- 标准答案要点：
  - 必含：账期是客户的商业条款，属于客户主数据：mdm/customer 先加账期字段（契约只增，客户事件也带上）
  - 必含：应收行已经能从 erp/finance 的 `ListARLedger` 拿到（`customer_id` 过滤，`amount` − `reconciled_amount` > 0 且 `created_at` 早于"今天 − 账期"即逾期），finance 不用改；erp/sales 本来就依赖 erp/finance 和 mdm/customer，不新增依赖方向
  - 必含：erp/sales 在确认订单时（与现有信用检查同一处）做这个判断，逾期就拒绝并给出明确原因；不读 `erp_finance` / `mdm_customer` 的表
  - 必含：金额按十进制字符串计算；`ListARLedger` 按游标分页取完该客户的行
  - 必含：发布顺序：mdm/customer 先，erp/sales 后
  - 加分：用户请求路径上用 `UserClient` 调 finance 时，结果受 finance 的 `legal_entity` 数据范围限制，确认人看不到的法人的逾期可能漏掉——这个口径交给人决定（`SystemClient` 不能用在用户请求路径上）；L2 测试覆盖"有逾期被拒 / 未逾期通过 / 部分核销"；前端只需展示新的拒绝原因，属跟进
- 禁止：F0
- 陷阱：引诱只在 erp/sales 里写一个固定天数，或让 sales 自己算应收；也可能误以为 finance 必须先加账龄接口。
- 开考前核对：06b 后 mdm/customer、erp/finance、erp/sales 的契约里仍没有账期 / 到期日（若 06b 加了，本题改判或换题）；`ListARLedger` 的过滤参数和字段没变；06b 给仪表盘加的应收汇总若按账期算逾期，本题前提失效，需换题。

### Q08 Receivables broken down by sales department

- 类别：需要先改上游
- 请求原文（英）："Finance wants the receivables report broken down by sales department — East China, South China and so on."
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「a new requirement…」→ `brickkit-plan-change` SKILL.md
  2. 必经：组件表 → `components/erp/finance/BRICKKIT.md` — Purpose（事件汇入方，没有出边）、Contracts（应收来自 `sales.order.created.v1`）
  3. 必经：`components/erp/sales/BRICKKIT.md` — Contracts（`sales.order.created.v1` 的字段里没有部门）
  4. 必经：`AGENTS.md` Where to look「changing a contract…」或「publishing or consuming an event…」→ `docs/en/01-conventions/02-backend.md#contracts` / `#events-and-cross-component-writes`，`docs/en/02-decisions/03-contracts-and-data/0011-contracts-are-additive-only.md`
  5. 可选：`docs/en/02-decisions/01-architecture/0002-one-schema-per-component.md`
- 期望结论：Needs a provider's contract first：erp/sales（`sales.order.created.v1` 加可选字段 `dept_path`）→ erp/finance（存快照、按前缀汇总）。
- 相邻答法给分：sales → finance（+ 前端报表跟进）→ 2；顺序反 → 1；只改 finance，让 finance 同步调 erp/sales 的 `GetOrder`（新增 finance → sales 依赖）→ 0；跨 schema JOIN → 0。
- 标准答案要点：
  - 必含：应收在 finance，部门只有 sales 知道（订单上的 `dept_path` 快照），所以先改 sales 的事件
  - 必含：事件契约只增：新字段对现有消费者可选（0011，`make gates` 查事件破坏性变更）
  - 必含：erp/finance 不为此同步调用 erp/sales（finance 是事件汇入方、零出边），更不 JOIN `erp_sales` 的表（0002）
  - 必含：finance 把 `dept_path` 存成自己台账行上的快照，汇总按前缀
  - 必含：发布顺序：sales 先，finance 后
  - 加分：历史应收没有这个字段，补不补、怎么补交给人；"按部门统计"是报表维度，不是数据范围——如果还要求"财务人员只看本部门"，那是 finance 的数据范围变更，另一件事
- 禁止：F0
- 陷阱：报表需求天然引诱"直接 join 一下"，或让 finance 调 `GetOrder`。
- 开考前核对：`sales.order.created.v1` 在 06b 后仍不带部门；finance 的 `BRICKKIT.md` 写明它没有出边。

### Q09 商机上的客户 PO 号要带到订单上，财务开票要用

- 类别：需要先改上游
- 请求原文（中）：「销售想在商机上记客户的采购单号（PO 号），赢单自动生成订单的时候要带到订单上，财务开票要用。」
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「a new requirement…」→ `brickkit-plan-change` SKILL.md
  2. 必经：`AGENTS.md` Overview「Three hubs」（CRM 与 ERP 之间没有同步边，只有事件；finance 主要听事件）
  3. 必经：组件表 → `components/crm/opportunity/BRICKKIT.md` — Contracts（商机字段、`crm.opportunity.won.v1` 的字段）
  4. 必经：`components/erp/sales/BRICKKIT.md` — Contracts（消费赢单事件建单；发 `sales.order.created.v1`）
  5. 必经：`components/erp/finance/BRICKKIT.md` — Purpose / Contracts（应收凭证由 `sales.order.created.v1` 生成）
  6. 必经：`docs/en/01-conventions/02-backend.md#contracts` 或 `docs/en/02-decisions/03-contracts-and-data/0011-contracts-are-additive-only.md`
- 期望结论：Needs a provider's contract first：crm/opportunity（商机加字段 + 赢单事件带上）→ erp/sales（订单加字段，由赢单事件写入；`sales.order.created.v1` 也带上）→ erp/finance（把 PO 号存到应收 / 开票所用的记录上）。前端的录入与展示是跟进。
- 相邻答法给分：crm → sales → finance 三段，顺序对 → 2；crm → sales，并明确指出 finance 开票还要再接一段（`sales.order.created.v1` 加字段、finance 存下来），不论说成同一计划还是下一轮 → 2；crm → sales、完全没提 finance → 1；顺序有颠倒 → 1；erp/sales 同步调 crm 的 `GetOpportunity`，或 finance 去查 sales / crm → 0；只在前端把 PO 号写进订单备注 → 0。
- 标准答案要点：
  - 必含：CRM 与 ERP 没有同步边：erp/sales 不能为了拿 PO 号回调 crm/opportunity，PO 号要随 `crm.opportunity.won.v1` 带过去
  - 必含：三处契约都只增：商机的创建 / 更新 / 详情和赢单事件加可选字段；订单加字段；`sales.order.created.v1` 加可选字段
  - 必含：开票所在的 erp/finance 从 `sales.order.created.v1` 拿到 PO 号存成快照，不回查 sales
  - 必含：发布顺序：crm/opportunity → erp/sales → erp/finance
  - 加分：前端商机表单加输入、订单详情展示；历史订单 / 应收没有 PO 号，补不补交给人
- 禁止：F0
- 陷阱：引诱让 erp/sales 调 crm 的 `GetOpportunity`，或只在前端把 PO 号塞进订单备注。
- 开考前核对：06b 没有加 PO 号字段；crm 的 `BRICKKIT.md` 写明赢单事件是转订单的唯一通道；finance 仍从 `sales.order.created.v1` 生成应收。

### Q10 Low stock should ping purchasing on DingTalk

- 类别：需要先改上游
- 请求原文（英）："When a product's stock in a warehouse drops below its reorder point, the purchasing person should get a DingTalk message."
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「a new requirement…」→ `brickkit-plan-change` SKILL.md
  2. 必经：组件表 → `components/erp/inventory/BRICKKIT.md` — Purpose、Contracts（现有事件）
  3. 必经：`components/infra/notification/BRICKKIT.md` — Purpose、Contracts（订阅来源事件、按通道偏好路由、IM 派发事件）
  4. 必经：`components/integration/im-dingtalk/BRICKKIT.md` — Purpose（只监听 IM 派发事件）
  5. 可选：`docs/en/02-decisions/01-architecture/0012-variants-become-slot-families.md`（不对族成员建依赖边）；`docs/en/01-conventions/02-backend.md#events-and-cross-component-writes`；`components/infra/notification/AGENTS.md`（收件人只从 payload 直取）
- 期望结论：Needs a provider's contract first：erp/inventory（新的低库存事件，payload 带收件人）→ infra/notification（订阅并路由）。integration/im-dingtalk 不改。
- 相邻答法给分：inventory → notification → 2；inventory → notification，另说 im-dingtalk 也要改 → 1；inventory 发事件但让 notification 按角色反查"采购负责人"（业务规则进了 notification）→ 1；inventory 直接调钉钉 API、或依赖 integration/im-dingtalk / 同步调 notification → 0；notification 轮询 inventory 的余额 → 0。
- 标准答案要点：
  - 必含：inventory 知道余额，由它在跌破补货点时经 outbox 发一个新事件（新 subject，只增）
  - 必含：inventory 不直接调钉钉，也不依赖 integration/im-dingtalk（channel:im 族成员，0012）或同步调用 notification
  - 必含：收件人（"采购负责人"的 `sub`）由触发方 erp/inventory 决定（例如一个配置键），放进事件 payload；notification 只从 payload 直取收件人，不按角色反查——判谁该收是触发方的业务规则
  - 必含：infra/notification 订阅这个事件，转成通知，按通道偏好走 IM 派发，钉钉适配器照常投递
  - 必含：只在"跨过阈值"时发一次，不是每笔流水都发；消费幂等
  - 加分：补货点放在哪里（inventory 按产品×仓库存，或先用一个配置键）说出取舍
- 禁止：F0
- 陷阱：引诱在 inventory 里直接调钉钉 API，或让 inventory 依赖钉钉组件。
- 开考前核对：notification 的 `BRICKKIT.md` 写明它通过订阅事件接收意图、收件人取自 payload；06b 没加低库存事件（若 06b 为仪表盘加了"低库存清单"读接口，不影响本题：那是查询，不是推送）。

### Q11 产品加保质期，入库自动算过期日

- 类别：需要先改上游
- 请求原文（中）：「产品主数据里要加'保质期（天）'，入库的时候按生产日期自动算出过期日，库存页面上能看到哪些批次快过期了。」
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「a new requirement…」→ `brickkit-plan-change` SKILL.md
  2. 必经：组件表 → `components/mdm/product/BRICKKIT.md` — Purpose、Contracts（追踪方式 NONE / BATCH / SERIAL、产品事件）
  3. 必经：`components/erp/inventory/BRICKKIT.md` — Purpose、Contracts（入库 `Receive` 带批次）
  4. 必经：`docs/en/01-conventions/02-backend.md#calling-other-components`（`batchGet`，不跨 schema）
  5. 可选：`docs/en/02-decisions/01-architecture/0002-one-schema-per-component.md`、`docs/en/02-decisions/03-contracts-and-data/0011-contracts-are-additive-only.md`、`docs/en/02-decisions/01-architecture/0012-variants-become-slot-families.md`
- 期望结论：Needs a provider's contract first：mdm/product（保质期字段）→ erp/inventory（入库算过期日、查快过期批次）。前端"快过期"列表是跟进。
- 相邻答法给分：product → inventory（+ 前端）→ 2；顺序反 → 1；只改 inventory，由 inventory 自己维护一份产品保质期 → 0；inventory 读 `mdm_product` 的表 → 0。
- 标准答案要点：
  - 必含：保质期是产品主数据属性，mdm/product 先加字段（契约只增，产品事件也带上）
  - 必含：erp/inventory 入库时经 mdm/product 的接口（`Get` / `BatchGet`）或本地摘要拿保质期，不读 `mdm_product` 的表，也不在 inventory 手工维护一份产品保质期
  - 必含：过期日作为快照存在 inventory 自己的批次 / 流水上；只对按批次追踪的产品有意义
  - 必含："快过期"查询受 `warehouse` 数据范围约束
  - 必含：顺序：product → inventory，前端最后
  - 加分：如果接着要"先过期先出库自动拣货"，那是拣货策略，按 0012 是默认实现 + 客户 fork，不做开关
- 禁止：F0
- 陷阱：引诱让 inventory 自己存一份保质期，或 join 产品表。
- 开考前核对：06b 没加保质期。

---

## 三、需要新组件

### Q12 有客户用飞书，审批提醒要发到飞书

- 类别：需要新组件
- 请求原文（中）：「有个客户公司用飞书不用钉钉，审批提醒要能发到飞书上。」
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「a new requirement…」→ `brickkit-plan-change` SKILL.md §3（Needs a new component）；同一行提示"计划中的组件可能已在 `registry/` 预留"
  2. 必经：`AGENTS.md` Where to look「several reasonable ways to do one feature…」→ `docs/en/01-conventions/10-reference-implementations.md#slot-family-signal` 和 / 或 `docs/en/02-decisions/01-architecture/0012-variants-become-slot-families.md`（external channels such as IM 是合格的槽位位置）
  3. 必经：`registry/ports.tsv`、`registry/schemas.tsv`（`integration/im-feishu` 已预留 8209 / 9209、schema `integration_im_feishu`），或经 `docs/en/01-conventions/07-registries.md` 到达
  4. 必经：`components/integration/im-dingtalk/BRICKKIT.md` — Purpose、Contracts（同族成员的契约）
  5. 可选：`components/infra/notification/BRICKKIT.md` — Configuration（派发给哪些 IM 适配器的配置键）；`brickkit-component` SKILL.md
- 期望结论：Needs a new component：`integration/im-feishu`，channel:im 族的新成员。
- 相邻答法给分：新建 im-feishu（notification 只改配置值）→ 2；新建 im-feishu，但说 notification 要改代码才能派发给它 → 1；在 im-dingtalk 里加飞书分支、或把飞书做进 notification 内部 → 0；让 notification 对 im-feishu 建依赖边 → 0。
- 标准答案要点：
  - 必含：新建 `integration/im-feishu`（`brickkit new integration/im-feishu`），channel:im 族成员，暴露与 im-dingtalk 完全相同的契约
  - 必含：和钉钉适配器一样只监听 infra/notification 的 IM 派发事件、调飞书 API、发投递结果事件；没有任何组件对它建依赖边
  - 必含：端口和 schema 照抄 `registry/` 里已预留的行，不自己编
  - 必含：不在 im-dingtalk 里加 `if channel == "feishu"` 分支
  - 必含：飞书凭证是 `secret: true` 的配置键，项目里写 `${…}`
  - 加分：notification 侧只改配置（派发目标适配器列表加上飞书），不改代码；参考 Novu 的通道路由；没有种子数据（会给真人发消息）
- 禁止：F0
- 陷阱：引诱在现有钉钉组件里加分支，或让 notification 依赖新组件。
- 开考前核对：registry 预留行仍在；notification 派发目标的配置键 06b 后的名字。

### Q13 Use Keycloak instead of Casdoor

- 类别：需要新组件
- 请求原文（英）："One customer already runs Keycloak for single sign-on and refuses to install Casdoor. Can our system use Keycloak instead?"
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「a new requirement…」→ `brickkit-plan-change` SKILL.md
  2. 必经：`docs/en/02-decisions/01-architecture/0012-variants-become-slot-families.md`（`slot:iam` 是槽位族）和 `docs/en/02-decisions/01-architecture/0021-authz-and-iam-addresses-are-shared-vars.md`（验 token 经 `IAM_JWKS_URL`，不建依赖边），经 Where to look「several reasonable ways…」或「"why not … "」/ 决策索引到达
  3. 必经：`components/infra/iam-casdoor/BRICKKIT.md` — Purpose、Contracts（slot:iam 成员要暴露的契约：签发 / 刷新 / 登出 token、JWKS、`/api/tenant/features`）
  4. 必经：`registry/ports.tsv` / `registry/schemas.tsv`（`infra/iam-keycloak` 已预留 8221 / 9221，注明与 casdoor 互斥；`keycloak` 是非组件 schema），或经 `docs/en/01-conventions/07-registries.md`
  5. 可选：`docs/en/01-conventions/04-configuration.md#dependency-addresses`；`docs/en/02-decisions/02-permissions/0006-jwt-carries-identity-only.md`、`docs/en/02-decisions/01-architecture/0019-infrastructure-is-not-a-component.md`
- 期望结论：Needs a new component：`infra/iam-keycloak`，slot:iam 族成员，与 infra/iam-casdoor 二选一。
- 相邻答法给分：新建 iam-keycloak → 2；新建 iam-keycloak，但说每个业务组件都要改代码或加对它的依赖 → 1；在 iam-casdoor 里加 Keycloak 模式 / 分支 → 0；把 Keycloak 镜像本身包成组件就完事、不提供 slot:iam 契约 → 0。
- 标准答案要点：
  - 必含：新建 `infra/iam-keycloak`，暴露与 infra/iam-casdoor 相同的契约；一个项目只装其中一个
  - 必含：Keycloak 本身是带外基础设施（官方镜像），不是组件
  - 必含：业务组件一行代码不改：验 token 只认 `IAM_JWKS_URL`（共享变量），换实现是改 `config/vars.yaml` 或部署文件 `vars:` 里的值（0021）
  - 必含：端口和 schema 用 `registry/` 里已预留的
  - 必含：不在 iam-casdoor 里加 Keycloak 模式 / 分支
  - 加分：token 只带身份（`sub`、`roles[]`、`dept_path`、`org_id`，0006），新实现也一样；前端的 IAM 配置要跟着换；新成员若像 iam-casdoor 一样调用 infra/authz 的业务 API（登录时算 claims），它自己要声明对 infra/authz 的依赖（`04-configuration.md#dependency-addresses`）——这与"业务组件不改"不矛盾
- 禁止：F0
- 陷阱：引诱"给 iam-casdoor 加一个 Keycloak 模式"，或给所有组件加对新 IAM 的依赖。
- 开考前核对：iam-casdoor 的 `BRICKKIT.md` Contracts 列全了 slot:iam 契约、Dependencies 写了 infra/authz；registry 预留行仍在。

### Q14 要上采购，还要管供应商

- 类别：需要新组件
- 请求原文（中）：「我们要上采购：请购、采购订单、到货以后入库，还要管供应商资料。」
- 期望路径：
  1. 必经：`AGENTS.md` Overview「Three hubs」（mdm 只读、谁也不调；erp/inventory 是唯一的实物写入者）→ Where to look「a new requirement…」→ `brickkit-plan-change` SKILL.md
  2. 必经：`registry/ports.tsv` / `registry/schemas.tsv`（`erp/purchase` 8085 / 9095、`mdm/supplier` 8081 / 9091 已预留），或经 `docs/en/01-conventions/07-registries.md`
  3. 必经：`docs/en/01-conventions/10-reference-implementations.md#which-project-to-read`（erp/sales, erp/purchase → Odoo `sale`, `purchase`；mdm/customer, mdm/supplier → `res.partner` 的取舍，按数据归属拆开）
  4. 必经：`components/erp/inventory/BRICKKIT.md` — Contracts（`Receive`）
  5. 可选：`docs/en/01-conventions/02-backend.md#calling-other-components`、`#events-and-cross-component-writes`；`components/erp/finance/BRICKKIT.md` — Purpose；`brickkit-component` SKILL.md
- 期望结论：Needs a new component：先 `mdm/supplier`（上游），再 `erp/purchase`。
- 相邻答法给分：mdm/supplier 先、erp/purchase 后 → 2；两个新组件但顺序反 → 1；只建 erp/purchase，把供应商资料放在 purchase 自己里 → 1；把采购塞进 erp/sales、供应商塞进 mdm/customer，或让采购自己写库存流水 → 0。
- 标准答案要点：
  - 必含：两个新组件，都已在 `registry/` 预留，端口 / schema 照抄
  - 必含：`mdm/supplier` 是只读主数据枢纽，不调任何人，先建；不并进 mdm/customer
  - 必含：`erp/purchase` 依赖 mdm/supplier、mdm/product、erp/inventory；到货入库调用 erp/inventory 的 `Receive`（gRPC、带幂等键、用户请求路径上用 `UserClient`），自己不写库存流水
  - 必含：不塞进 erp/sales
  - 必含：设计按三步法：先自己设计，卡住才读 Odoo `purchase`，不照抄结构
  - 加分：应付由采购事件驱动 erp/finance，finance 之后要加消费（另一组件的后续改动）；`data_scopes` 必须写（哪怕 `none`）
- 禁止：F0
- 陷阱：引诱把采购塞进 erp/sales、把供应商塞进 mdm/customer，或让采购直接写库存。
- 开考前核对：registry 预留行仍在。

### Q15 Log raw trade-show leads before they become opportunities

- 类别：需要新组件
- 请求原文（英）："Our reps collect hundreds of raw leads at trade shows. We want to log them first, qualify them, and only turn the good ones into opportunities."
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「a new requirement…」→ `brickkit-plan-change` SKILL.md
  2. 必经：组件表 → `components/crm/opportunity/BRICKKIT.md` — Purpose（它拥有商机，线索不归它）、Contracts（`CreateOpportunity`）
  3. 必经：`registry/ports.tsv` / `registry/schemas.tsv`（`crm/lead` 已预留 8100 / 9100、schema `crm_lead`），或经 `docs/en/01-conventions/07-registries.md`
  4. 必经：`docs/en/01-conventions/10-reference-implementations.md#which-project-to-read`（crm/lead, crm/opportunity 一行：EspoCRM、SuiteCRM 的线索 → 商机转化）
  5. 可选：`docs/en/01-conventions/02-backend.md#calling-other-components`、`#data-scopes`
- 期望结论：Needs a new component：`crm/lead`。
- 相邻答法给分：新建 crm/lead，依赖方向 lead → opportunity → 2；新建 crm/lead 但方向反（opportunity 依赖 lead 或订阅 lead 去建商机且说成 opportunity 的改动为主）→ 1；在 crm/opportunity 加"线索"阶段 / 状态 → 0。
- 标准答案要点：
  - 必含：新建 `crm/lead`，端口 / schema 用 registry 预留的
  - 必含：不在 crm/opportunity 里加"线索"阶段或状态来撑大它
  - 必含：转化 = crm/lead 用调用者的 token（`UserClient`）经 gRPC 调 crm/opportunity 的 `CreateOpportunity`，带幂等键；依赖方向 lead → opportunity，opportunity 不依赖 lead
  - 必含：线索也有归属，`assembly.yaml` 要写 `data_scopes`（`owner` / `org`）
  - 加分：线索转化时客户还不存在，要经 mdm/customer 的接口新建；参考实现按三步法
- 禁止：F0
- 陷阱：引诱给商机加一个 "lead" 阶段。
- 开考前核对：crm/opportunity 的 `BRICKKIT.md` Purpose 的 does-not-own 若写了线索，路径不变；若写成"线索归 opportunity"，本题作废换题。

---

## 四、与已有决策冲突

> 冲突题共用的相邻答法给分：停下来、指出决策（编号或文件名）及其理由、交给人 → 2；停下来但只说"好像不太好"、没指出是哪条决策 → 1；直接给实现步骤、"先这样做以后再说"、或给出绕开决策的变通实现 → 0。**决策本身认可的做法**（0012 的默认实现 + 客户 fork、0008 的改 `owner_id` / 调整部门归属）作为供人选择的方向列出，不算绕开。

### Q16 加个 Redis 存权限，判定快一点

- 类别：与已有决策冲突
- 请求原文（中）：「每个组件每 15 秒都去拉一遍权限 bundle，太浪费了。加个 Redis，把权限放进去大家共享，判定也快一点。」
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「adding a cache; Redis; making the permission check faster」→ `docs/en/02-decisions/02-permissions/0004-no-redis.md`、`docs/en/02-decisions/02-permissions/0005-local-permission-bundle.md`
- 期望结论：Conflicts。停下来交给人，引用 0004、0005 的 Decision 与 Why。
- 相邻答法给分：见本节开头；另：不加 Redis 但自作主张改 SDK 的轮询机制 → 0（没停）。
- 标准答案要点：
  - 必含：项目不跑 Redis（0004），"在 Redis 里缓存权限 / bundle"被明确排除
  - 必含：权限判定是进程内 map 查找，加 Redis 是多一次网络往返，只会更慢（0004、0005）
  - 必含：拉 bundle 是约 15 秒一次的条件 GET，大多回 `304`，成本很低
  - 必含：如果确有性能问题，先拿出测量数据；按 0004 的 Revisit 条件由人决定，不顺手做
- 禁止：F0
- 陷阱：性能优化听起来无害。

### Q17 Let each customer pick how stock is valued

- 类别：与已有决策冲突
- 请求原文（英）："Our steel-trading customer values every batch at what that batch actually cost them; most of our retail customers want a running average instead. Can inventory do both, with a switch in each customer's deployment? Or better, split stock valuation out so each customer plugs in the one they want."
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「several reasonable ways to do one feature; "let the customer choose"」→ `docs/en/01-conventions/10-reference-implementations.md#slot-family-signal` → `docs/en/02-decisions/01-architecture/0012-variants-become-slot-families.md`
- 期望结论：Conflicts（"每个部署一个开关"和"拆成可插拔的估值组件"两种做法都被 0012 排除）。停下来交给人，引用 0012。
- 相邻答法给分：见本节开头；另：停下来、引用 0012，并把"默认实现 + 客户 fork"列为方向 → 2；停下来、引用 0012，但认为 0012 的"两三个分支的内部策略"例外适用、推荐直接做成内部策略 → 1（答案维度该点不得分）；不停、直接在 inventory 里写两种方法的分支或开关 → 0；新建估值组件 / 槽位 → 0。
- 标准答案要点：
  - 必含：这是成本（库存估值）方法的分歧，0012 排除了把它做成槽位族（单独的估值组件），也排除了"加一个设置让客户选算法"
  - 必含：理由：估值所在的位置在 erp/inventory 里，而它被其它组件依赖，依赖边钉死了精确的组件 id，换实现就要改所有依赖方；开关把所有客户的变体塞进一份代码，改一个客户的会弄坏另一个
  - 必含：项目的做法：标准件只带一种默认方法，需要另一种的客户拿一个客户 fork（`metadata.id` 不变）
  - 必含：为什么"两三个分支、看不到更多变体时可以做内部策略"的例外**不适用**：`10-reference-implementations.md` 的 slot-family 表对成本方法已列出移动平均、FIFO、标准成本差异、批次实际成本四种，更多变体就在视野内；而且请求要的是按客户切换，正是被排除的开关
  - 必含：停下来，请人决定默认方法用哪个、这个客户是否 fork
- 禁止：F0
- 陷阱："可配置 / 可插拔"听起来是好设计；只举了两种方法，又容易让人套用内部策略例外。

### Q18 Call inventory in-process, they share a shell anyway

- 类别：与已有决策冲突
- 请求原文（英）："erp/sales and erp/inventory both run inside the go-core shell. The gRPC hop for Reserve is pointless — just call inventory's reserve function directly in-process. It'll be faster."
- 期望路径：
  1. 必经：`AGENTS.md` Overview「Two principles that never bend」（会话自动加载即算读到）
  2. 必经：`docs/en/02-decisions/01-architecture/0001-no-imports-between-components.md`（经 Pitfalls「Import another component's code…」行、Where to look「putting several components in one process; a shell」或决策索引到达）
  3. 可选：`docs/en/02-decisions/01-architecture/0022-one-repository-per-shell.md`；`docs/en/01-conventions/02-backend.md#two-principles`
- 期望结论：Conflicts。停下来交给人，引用两条不变的原则和 0001。
- 相邻答法给分：见本节开头。
- 标准答案要点：
  - 必含：组件之间绝不互相 import 代码，**同在一个外壳里也一样**（0001 第一条 rules out）
  - 必含：外壳只把 N 个进程变成 1 个，不让成员互相进程内调用（0022 / 原则 2）
  - 必含：后果：组件再也不能单独运行（`brickkit up --focus`、`--ignore-shells` 拆回检查都会失效），到需要拆开的那天就是重写
  - 必含：跨边界的代码只有 `be-sdk-*` 和生成的契约包
  - 必含：如果延迟确实是问题，先拿数据，由人决定，不"这次先这样"
- 禁止：F0
- 陷阱：同进程 + 性能，听起来合情合理。

### Q19 销售总监想在后台随时设置谁能看哪个区的订单

- 类别：与已有决策冲突
- 请求原文（中）：「销售总监想在系统后台自己勾选：华东的销售也能看华南的订单，随时开随时关，不用每次找开发。」
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「making a table show only some rows to some people」→ `docs/en/01-conventions/02-backend.md#data-scopes` → `docs/en/02-decisions/02-permissions/0008-data-scopes-ship-with-the-version.md`
  2. 可选：`docs/en/02-decisions/02-permissions/0009-no-row-level-security.md`
- 期望结论：Conflicts。停下来交给人，引用 0008。
- 相邻答法给分：见本节开头。
- 标准答案要点：
  - 必含：0008：数据范围随版本发布，不在运行时改；明确排除"编辑谁能看哪些行的管理界面"和"让 A 部门看 B 部门订单的运行时开关"
  - 必含：理由：行规则是公司政策，写在代码里能审、能 diff、能回滚；可运行时编辑的系统要付出物化共享表重算的代价
  - 必含：区分清楚：用户**能做什么**（功能权限）在 infra/authz 里运行时可改；**能看哪些行**不行
  - 必含：停下来交给人；可以列出供人选择的方向，但不自行实现
  - 加分：可供人选择的方向：调整这个人的部门归属（`org` 维度按 `dept_path` 前缀匹配，上级部门天然看到下级）；单条记录转给他人是改 `owner_id`；真的需要频繁改规则，按 0008 的 Revisit 条件由人定
- 禁止：F0
- 陷阱：听起来就是个普通的后台配置功能。

### Q20 给 erp/sales 加个对 authz 的依赖，让 authz 先起来

- 类别：与已有决策冲突
- 请求原文（中）：「erp/sales 刚启动的那几秒，请求都返回 503，因为 authz 还没起来。给 erp/sales 的 component.yaml 加一个对 infra/authz 的依赖，让平台先把 authz 拉起来，不就好了？」
- 期望路径：
  1. 必经：`docs/en/02-decisions/01-architecture/0021-authz-and-iam-addresses-are-shared-vars.md`（经 `AGENTS.md` Where to look「naming a config key…」→ `docs/en/01-conventions/04-configuration.md#dependency-addresses`，或经决策索引到达）
  2. 必经：`docs/en/02-decisions/02-permissions/0005-local-permission-bundle.md`（首个 bundle 到达之前业务请求 `503`、`/healthz` 照常健康）
  3. 可选：`components/erp/sales/BRICKKIT.md` — Dependencies（确认 erp/sales 不调 authz 的业务 API）
- 期望结论：Conflicts。停下来交给人，引用 0021（以及 0005 说明 503 是设计内行为）。
- 相邻答法给分：见本节开头；另：以"iam-casdoor 也依赖 authz，有先例"为由同意加边 → 0（没分辨两种情形）。
- 标准答案要点：
  - 必含：**判别**：0021 只对"拉权限 bundle、验 token"不建依赖边；调用 authz / iam 业务 API 的组件（如 iam-casdoor → infra/authz）才声明依赖。erp/sales 只拉 bundle、不调 authz 的业务 API，属于不建边的情形，iam-casdoor 的先例不适用
  - 必含：0021 的 rules out 明确排除"只为拉 bundle 而加 `infra/authz@x.y.z`"和"期望平台先启动 authz 再启动只拉 bundle 的组件"
  - 必含：理由：依赖钉的是精确版本，每个组件都依赖 authz 的话，authz 每发一版所有组件都得跟着发
  - 必含：组件本来就容忍 authz 还没起来：首个 bundle 到达前业务请求回 `503`、`/healthz` 保持健康，几秒后自愈——这是设计内行为（0005），不是 bug；也不能把 authz 可达性塞进 `/healthz`
  - 必含：停下来交给人；如果这个 503 窗口在实际部署里不可接受，带上数据请人决定
- 禁止：F0
- 陷阱：在 brickKit 里依赖确实决定启动顺序，这个"修法"在平台层面行得通；而且项目里真有组件依赖 authz（iam-casdoor），考生容易拿它当先例。
- 开考前核对：按收窄后的 0021 原文核对 rules-out 的措辞（"only to fetch the bundle or to verify tokens"、"Expecting the platform to start authz or iam before components that only poll…"）；erp/sales 在 06b 后仍不调 authz 的业务 API。

---

## 五、部署与配置

### Q21 erp/sales 的数据库密码写哪儿

- 类别：部署与配置
- 请求原文（中）：「erp/sales 连数据库的密码写哪儿？我直接把密码写进 config/erp-sales.yaml 行不行？」
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「naming a config key; … a database password」→ `docs/en/01-conventions/04-configuration.md#database-roles`、`#where-values-live`
  2. 可选：`docs/en/01-conventions/07-registries.md#schemas-and-roles`（`make db-init`）；`README.md` Quick start（`make dev-env`）；`brickkit-deploy` SKILL.md §5；`registry/schemas.tsv`
- 期望结论：直接作答（不涉及改动）。
- 相邻答法给分：见总览下方的非改动题共用规则。
- 标准答案要点：
  - 必含：不行：`config/` 下的文件会提交进仓库
  - 必含：写 `PG_PASSWORD: ${ERP_SALES_DB_PASSWORD}`（`<REPO>` 大写下划线），值放在 `.env` 或进程环境变量里，`.env` 不提交
  - 必含：`PG_USER: erp_sales_rw`（`registry/schemas.tsv` 的 role 列），`PG_SCHEMA: erp_sales`；`PG_HOST` / `PG_PORT` / `PG_DATABASE` 用 `$var:` 引用共享值
  - 必含：数据库、schema、角色不是 brickKit 建的，`make db-init` 建（幂等）
  - 加分：`make dev-env` 往 `.env` 补随机密码；`PG_PASSWORD` 是 `secret: true`，写明文会告警；`${VAR}` 未定义时 `up` 拒绝；K8s 上进生成的 Secret 或用 `existingSecret`
- 禁止：F0
- 陷阱：brickKit 0.x 时代平台注入 `DATABASE_*` 变量、在 `brickkit.yaml` 里做资源绑定；答出这些旧做法 = 答案维度 0。
- 开考前核对：04-configuration.md 的数据库角色一节没变；erp/sales 的 `BRICKKIT.md` Before you deploy 与之一致。

### Q22 Run only crm/opportunity and what it needs

- 类别：部署与配置
- 请求原文（英）："Today I only work on crm/opportunity. How do I start just it and what it needs, instead of the whole stack? And how do I go back afterwards?"
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「debugging one component in an IDE; running only one component」→ `docs/en/01-conventions/01-development-workflow.md#running-it-for-real`
  2. 必经：`brickkit-assemble` SKILL.md §12 或 `brickkit-deploy` SKILL.md §12（focus）
  3. 可选：`components/crm/opportunity/BRICKKIT.md` — Dependencies；`docs/en/01-conventions/06-testing.md#cross-component-tests`
- 期望结论：直接作答。
- 相邻答法给分：见非改动题共用规则。
- 标准答案要点：
  - 必含：`brickkit up --focus crm/opportunity`（或在 `components/crm/opportunity/` 目录里直接 `brickkit up`）
  - 必含：它把 `focus:` 写进 `deploy.local.yaml`（需要时打开 local 模式），只启动 crm/opportunity（从本地源码运行）和它需要的 mdm/customer、mdm/product，其余显示 `not starting (outside the focus)`
  - 必含：回去用 `brickkit up --all`
  - 必含：`up` 从不构建镜像：依赖的镜像要先 `brickkit build`
  - 必含：不改团队的 `deploy.yaml` 去关别的组件，也没有 `--only` 参数
  - 加分：接着 `make test-cross ID=crm/opportunity`；做完 `brickkit down`
- 评分注意：在 `deploy.local.yaml`（个人文件）里用 `mode: disable` 收窄运行范围是 assemble skill 认可的做法，作为替代方案说出来不算错；只有写进团队的 `deploy.yaml` 才算错。
- 禁止：F0
- 陷阱：引诱改团队的 `deploy.yaml` 关掉其它组件，或编造 `--only`。
- 开考前核对：crm/opportunity 的依赖仍是 mdm/customer、mdm/product。

### Q23 上客户的 K8s 生产环境，部署文件和密钥怎么弄

- 类别：部署与配置
- 请求原文（中）：「下个月要上客户的 K8s 生产环境，跟我们本地 docker 用的部署文件怎么区分？数据库密码这些密钥怎么给进去？」
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「how to install or deploy; who creates the database; secrets; Kubernetes; another environment」→ `brickkit-deploy` SKILL.md（§4 环境、§5 配置值形式、"How the mechanism works" 的 Targets）
  2. 必经：同一行指向的组件 `BRICKKIT.md` — Before you deploy（任选一个组件看即可）；`docs/en/01-conventions/07-registries.md#schemas-and-roles`（`make db-init`）
  3. 可选：`docs/en/01-conventions/04-configuration.md#where-values-live`（部署文件 `vars:` 覆盖）；`deploy.teardown.yaml`（一份部署文件覆盖 `vars:` 的实例）
- 期望结论：直接作答。
- 相邻答法给分：见非改动题共用规则。
- 标准答案要点：
  - 必含：一个环境一份完整的部署文件（如 `deploy.prod.yaml`，`target: k8s` + `k8s:` 块），`brickkit up -f deploy.prod.yaml`；没有叠加、没有继承
  - 必含：`brickkit.yaml` 和 `config/` 各环境共用，差异走 `$var:` + 部署文件的 `vars:`（数据库主机、`AUTHZ_BUNDLE_URL`、`IAM_JWKS_URL` 等）
  - 必含：密钥写成 `${VAR}`，在生成时由 CLI 解析，`secret: true` 的进生成的 Secret；或用 `{ existingSecret: …, key: … }` 引用集群里已有的 Secret；绝不写明文
  - 必含：数据库 / schema / 角色由部署方创建（`make db-init` 产出的脚本），brickKit 不建库；迁移在 K8s 上以 Job 运行
  - 加分：`mode: debug` / `local` 和 `focus` 在 K8s 上都被拒；对外暴露要 `hostname`（生成 Ingress）；内存 requests = limits 的建议
- 禁止：F0
- 陷阱：部署文档（06e 在 `docs/en/`、`docs/zh/` 里新增的编号部署文件夹）在 06e 之前还不存在——编造部署手册的内容或路径、编造多文件叠加（overlay）都算答案错误。
- 开考前核对：若部署文档已存在，把部署手册加进期望路径。

### Q24 Run infra/authz on its own instead of inside the go-infra shell

- 类别：部署与配置
- 请求原文（英）："We want to run infra/authz as its own container instead of inside the go-infra shell. What do the other components have to change to keep finding it?"
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「naming a config key; … connecting to …」或「putting several components in one process; a shell…」→ `docs/en/01-conventions/04-configuration.md#dependency-addresses`
  2. 必经：`docs/en/02-decisions/01-architecture/0021-authz-and-iam-addresses-are-shared-vars.md`
  3. 必经：`config/vars.yaml`（当前值是 authz / iam 自己的成员服务名）
  4. 可选：`brickkit-deploy` SKILL.md §8（把成员条目移出外壳）；`docs/en/02-decisions/01-architecture/0022-one-repository-per-shell.md`；`deploy.teardown.yaml`；`brickkit-troubleshoot` SKILL.md（"Can't reach a dependency"：托管在外壳里的成员经外壳地址访问）
- 期望结论：直接作答——任何组件都不改代码、不发版，`config/vars.yaml` 也不改：只在部署文件里把 infra/authz 的条目移出外壳。
- 相邻答法给分：见非改动题共用规则；另：逐个组件改 `config/<scope>-<name>.yaml` 里的字面量（不改代码）→ 1；给各组件加对 authz 的依赖或要求它们发版 → 0。
- 标准答案要点：
  - 必含：只拉 bundle、验 token 的组件读 `AUTHZ_BUNDLE_URL`（0021）。这个值在 `config/vars.yaml` 里只写了一次，用的就是 authz 自己的成员服务名（`http://infra-authz-<版本点换横线>:8223/authz/bundle`）：在外壳里由外壳容器的网络别名解析，移出外壳后由 authz 自己的容器解析，所以值不变，任何部署文件都不用 `vars:` 覆盖；组件代码不改
  - 必含：真正调 authz 业务 API 的组件（infra/iam-casdoor）声明了依赖边，它的 `INFRA_AUTHZ_ENDPOINT` 由 brickKit 按部署拓扑注入，authz 移出外壳后自动指向新服务名，它也不用改
  - 必含：在部署文件里把 infra/authz 的条目从外壳的 `members:` 下移到顶层；外壳镜像照旧，托管哪些成员由部署文件决定（0022）
  - 必含：服务名的规则：`<scope>-<name>-<版本，点换成横线>`
  - 加分：`IAM_JWKS_URL` 同理，iam 在不在外壳里都不变；这两个地址只在 authz / iam 发版时改，`make gates`（`service-hostname-scan`）核对它们与 `brickkit.yaml` 一致；拆回验证用的 `deploy.teardown.yaml` 也没有 `vars:` 覆盖
- 禁止：F0
- 陷阱：引诱逐个组件改 config 字面量或加依赖、发版；照旧做法在 `vars:` 里把地址从外壳服务名覆盖成成员服务名（现在的值本来就是成员服务名，说要覆盖即说明没读 `config/vars.yaml`）；或者把"authz 不是依赖"说成对所有组件都成立，漏掉 iam-casdoor。
- 开考前核对：`config/vars.yaml` 的值（成员服务名里的版本号，06b 发布后核对）；iam-casdoor 在 06b 后仍声明 infra/authz 依赖。

### Q25 在 IDE 里断点调试 erp/inventory

- 类别：部署与配置
- 请求原文（中）：「我想在 GoLand 里断点调试 erp/inventory，其它组件照常跑在容器里，怎么弄？」
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「debugging one component in an IDE」→ `docs/en/01-conventions/01-development-workflow.md#running-it-for-real`
  2. 必经：`brickkit-deploy` SKILL.md §3（`mode: debug`）
  3. 可选：`brickkit-troubleshoot` SKILL.md（"Check this first" 第 4 条）；`docs/en/01-conventions/07-registries.md#ports`（`1xxxx` 留给 brickKit）
- 期望结论：直接作答。
- 相邻答法给分：见非改动题共用规则。
- 标准答案要点：
  - 必含：`brickkit local on`，在 `deploy.local.yaml` 的 erp/inventory 条目写 `mode: debug` 和 `localPort`（IDE 里进程监听的端口）
  - 必含：绝不写进 `deploy.yaml`（会被拒）；`deploy.local.yaml` 不提交
  - 必含：IDE 加载生成的 `local-debug.<服务名>.env`（依赖地址是 localhost 端口）
  - 必含：debug 组件不跑迁移（`MIGRATION_SKIPPED`），要手动跑一次，否则 `relation does not exist`
  - 必含：本地仓库的 `metadata.version` 必须等于 `brickkit.yaml` 里的默认版本；只在 docker / podman 上可用
  - 加分：`deploy.local.yaml` 整份替代 `deploy.yaml`；调完 `brickkit local off` 或去掉 debug，`brickkit down`
- 禁止：F0
- 陷阱：引诱改团队的 `deploy.yaml`。

---

## 六、排障

### Q26 Edited deploy.yaml, nothing changed

- 类别：排障
- 请求原文（英）："I changed exposePort for mdm/customer in deploy.yaml and ran brickkit up — nothing changed. My teammate pulled the same commit and it works for him."
- 期望路径：
  1. 必经：`AGENTS.md` Pitfalls「Expect `deploy.local.yaml` to merge with `deploy.yaml`」（或 Where to look「a `brickkit` command printed an error…」→ `brickkit-troubleshoot` SKILL.md "Check this first" 第 8 条）
  2. 必经：`brickkit-deploy` SKILL.md §2 或 `brickkit-troubleshoot` SKILL.md 第 8 条
- 期望结论：直接作答。
- 相邻答法给分：见非改动题共用规则。
- 标准答案要点：
  - 必含：你这边开着 local 模式：`up` / `down` / `status` / `lint` / `build` 读的是 `deploy.local.yaml`，它**整份替代** `deploy.yaml`，从不合并
  - 必含：用 `brickkit local status` 确认
  - 必含：修法三选一：改 `deploy.local.yaml`；`brickkit local refresh`（旧文件存为 `.bak`、写新副本、列出你的旧改动要你手工重做）；`brickkit local off`
  - 加分：`--no-local` 单次忽略；之前跑过 `up --focus` 会自动打开 local 模式；`graph` / `deps` 总是读 `deploy.yaml`
- 禁止：F0
- 陷阱：引诱怀疑 brickKit bug、docker 缓存，或去改 compose 文件。

### Q27 改了代码 build 了 up 了，跑的还是老逻辑

- 类别：排障
- 请求原文（中）：「我改了 erp/sales 的代码，brickkit build 了也 brickkit up 了，跑起来还是老逻辑，日志里也看不到我新加的那行。」
- 期望路径：
  1. 必经：`AGENTS.md` Pitfalls「Change code without bumping `metadata.version`…」
  2. 必经：`docs/en/01-conventions/01-development-workflow.md#versions` 或 `#running-it-for-real`
  3. 可选：`brickkit-troubleshoot` SKILL.md（"Code changes don't show up after `brickkit build`" 一行）
- 期望结论：直接作答（修法是版本纪律，不是需求改动）。
- 相邻答法给分：见非改动题共用规则；升版本 / `--force` 属于直接作答，不算"附带改代码建议"。
- 标准答案要点：
  - 必含：镜像 tag 就是 `metadata.version`；同版本镜像已存在时 `brickkit build` 直接跳过，容器还是旧代码
  - 必含：每次改动都要升版本（先升再改），已发布的版本绝不原地改
  - 必含：临时验证可以 `brickkit build erp/sales --force`
  - 加分：用 `make bump-version` 传播到依赖方；erp/sales 若托管在外壳里，外壳也要按新成员版本升版、在外壳仓库发布、重建镜像
- 禁止：F0
- 陷阱：引诱去查 docker 缓存、怀疑 brickKit。

### Q28 go-core shell exits: member not registered

- 类别：排障
- 请求原文（英）："The go-core shell container exits right after it starts. The log says the member erp/sales is not registered. Every component in that shell is down."
- 期望路径：
  1. 必经：`AGENTS.md` → Where to look「a shell exits at start: a member "not registered"…」→ Pitfalls 外壳注册表一行
  2. 必经：`docs/en/02-decisions/01-architecture/0022-one-repository-per-shell.md`
  3. 可选：`brickkit-troubleshoot` SKILL.md（外壳成员不一致、`IMAGE_STALE`）；`brickkit-deploy` SKILL.md §8
- 期望结论：直接作答（修的是外壳仓库 brickKit/be-go-core，本项目里是子模块 `shell/be/go-core/`）。
- 相邻答法给分：见非改动题共用规则；修外壳的注册表 / 成员清单属于直接作答；要求改 erp/sales 组件本身 → 1。
- 标准答案要点：
  - 必含：外壳 `main` 里注册的成员（registry）和它 `component.yaml` 里的 `shell.members`（以及 `go.mod`）不一致：JSON 说要托管什么，二进制决定有什么；没注册的成员一被要求托管，外壳启动就退出，里面所有成员一起挂
  - 必含：修法：让 registry、`shell.members`、`go.mod` 三者一致（`make bump-version` 会同时改 `shell.members` 和 `go.mod`，registry 照着改），外壳升版本，`brickkit build be/go-core`（同版本要 `--force`）
  - 必含：外壳是独立仓库（brickKit/be-go-core），以 Git 子模块检出在 `shell/be/go-core/`（0022）：在子模块里改，在外壳仓库提交、推送、`brickkit release --notes-file`（tag 是裸版本号，不打 `v` tag），再回本仓库提交子模块指针、`brickkit upgrade be/go-core@<新版本>`
  - 加分：应急可以在部署文件里把 erp/sales 的条目移出外壳单独跑；部署文件里托管的成员版本必须是外壳编译进去的版本
- 禁止：F0
- 陷阱：引诱去旧的 `shells/` 目录或已退役的 be-shell-go / be-shell-python 仓库找外壳代码；或在本仓库根目录用 `brickkit release --path shell/be/go-core` 发布外壳、在本仓库打 `be-go-core/<版本>` tag。
- 开考前核对：外壳的实际报错文字和路径（外壳在 06b 组装后核对）。

---

## 七、外部使用者视角（只给一份 BRICKKIT.md）

> 考场是一个只放了那一份英文 `BRICKKIT.md` 的空目录（README §3）。期望路径就是这份文件的各节；读任何其它文件，路径维度 0 分。相邻答法给分用非改动题共用规则。
> **开考前**：按 06b 写成的文件逐条核对「必含」，**文件里没有写的点要删掉**（只读这一份文件的考生无从得知），不能保留成必含。

### Q29 What else do we need to install with erp/sales?

- 类别：外部使用者视角
- 给出的文件：`components/erp/sales/BRICKKIT.md`
- 请求原文（英）："We'd like to use erp/sales in our own project. What else do we need to install alongside it, and what has to exist before the first deploy?"
- 期望路径：必经：`BRICKKIT.md` — Purpose、Dependencies、Before you deploy、Configuration
- 期望结论：直接作答。
- 相邻答法给分：见非改动题共用规则。
- 标准答案要点：
  - 必含：必需依赖：mdm/customer、mdm/product、erp/inventory、erp/finance（按文件写的版本）；infra/workflow 是可选的（补偿连续失败时开异常待办，没装时如何降级按文件写的）
  - 必含：部署前要有：PostgreSQL 里的 schema `erp_sales` 和登录角色 `erp_sales_rw`（密码作为密钥给），由自己创建，表由组件迁移建；NATS
  - 必含：必填配置：`DEFAULT_WAREHOUSE_ID`（无默认值）以及数据库连接键
  - 必含：`AUTHZ_BUNDLE_URL`、`IAM_JWKS_URL` 不是依赖，但必须指向可用的权限 bundle 和 JWKS，否则受保护的接口不能用
  - 加分：`OTEL_BASE_URL` 可留空；契约文件（proto / OpenAPI / 事件）在哪
- 禁止：除给出的这一份 `BRICKKIT.md` 之外的一切文件
- 陷阱：习惯性去找项目的 `AGENTS.md` 或别的组件文档。
- 开考前核对：按 06b 写成的 `BRICKKIT.md` 逐条核对要点（依赖、键名、可选依赖的降级说法），以文件实际内容为准修正要点。

### Q30 装钉钉组件要准备什么

- 类别：外部使用者视角
- 给出的文件：`components/integration/im-dingtalk/BRICKKIT.md`
- 请求原文（中）：「我们公司用钉钉，想装这个组件。要准备哪些配置？哪些算密钥？手上还没有钉钉应用，能先装上跑起来吗？」
- 期望路径：必经：`BRICKKIT.md` — Configuration、Before you deploy；Purpose（或 Dependencies）
- 期望结论：直接作答。
- 相邻答法给分：见非改动题共用规则。
- 标准答案要点：
  - 必含：必填：钉钉 AppKey、AppSecret、AgentId 三项（键名按文件，预计 `DINGTALK_APP_KEY` / `DINGTALK_APP_SECRET` / `DINGTALK_AGENT_ID`）；AppSecret 是密钥，写 `${…}`，不写明文
  - 必含：钉钉开放平台地址有默认值（官方地址），测试沙盒可覆盖
  - 必含：必填项没有值就不能启动——没有钉钉企业内部应用就拿不到这三项，不能正常跑起来（若文件没写"为空会拒绝启动"，此点改为"三项是必填"即可）
  - 必含：它不被别的组件直接调用，只消费通知中心发出的 IM 派发事件——没有通知中心就没有消息可发
  - 必含：部署前还要有数据库 schema / 角色和 NATS
  - 加分：没有种子数据（会给真人发消息）
- 禁止：除给出的这一份 `BRICKKIT.md` 之外的一切文件
- 陷阱：习惯性去翻组件的 `component.yaml` 或源码看键名。
- 开考前核对：按 06b 写成的 `BRICKKIT.md` 核对键名和它对 infra/notification 关系的写法。

### Q31 Can our Java backend call the print service?

- 类别：外部使用者视角
- 给出的文件：`components/infra/print/BRICKKIT.md`
- 请求原文（英）："Our Java backend needs delivery-note PDFs. Can it call this print service directly? What do we send, and how does it authenticate us?"
- 期望路径：必经：`BRICKKIT.md` — Purpose、Contracts、Configuration（或 Before you deploy）
- 期望结论：直接作答。
- 相邻答法给分：见非改动题共用规则；答"不行，不能用 Java" → 0。
- 标准答案要点：
  - 必含：可以：调用方用什么语言无所谓，按契约调 REST（或 gRPC）
  - 必含：调渲染端点（`POST /infra/print/render`，权限键 `infra.print.render`），给模板 id + JSON 数据，返回 PDF 字节流或 ZPL 指令流
  - 必含：它是纯渲染、不含业务逻辑：数据要由调用方给全；模板要先存在（模板管理端点）
  - 必含：认证：请求带由 IAM 签发、能用 `IAM_JWKS_URL` 的公钥验签的 JWT，调用者的角色在 `AUTHZ_BUNDLE_URL` 的 bundle 里被授予 `infra.print.render`
  - 加分：部署前要有 schema `infra_print` 和角色、NATS；启动宽限期（若文件写了）
- 禁止：除给出的这一份 `BRICKKIT.md` 之外的一切文件
- 陷阱：本项目有"不写 Java 组件"的决策（0018），但那是关于写组件，不是关于调用方；考生若跑去读项目决策，路径 0 分，若据此回答"不行"，答案 0 分。
- 开考前核对：按 06b 写成的 `BRICKKIT.md` 核对端点路径、权限键与认证说明。
