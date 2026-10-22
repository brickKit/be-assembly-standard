# 改动配方

本页把常见的几类改动要守的规则按动手的顺序串在一处：每一步写改哪里、守哪条规则，规则全文在链接里。写给在组件里动手的人与 AI：先在这里找到改动的类别，按步骤做，碰到要判断的地方再读链接的那一节。某个组件的特殊之处在它 `AGENTS.md` 的代码地图（“功能 → 从哪开始”）。

所有改动的共同收尾：同一次提交里改文档（意图类先改）、升版本（[开发流程与发布的版本](10-development-workflow.md#版本)）、跑组件的 `make test` 与 `make test-integration`。

## 给一个实体加字段

1. **先判断是不是这个组件的标准字段**：所有客户都要、组件自己的逻辑要读它的，是标准字段；只是某些客户想记录的（行业、来源渠道），用扩展字段（[协议 08 的扩展字段的边界](../06-protocols/08-extension-fields.md#扩展字段的边界)），标准逻辑从不读扩展字段。扩展字段的实现状态见组件的 `BRICKKIT.md`。
2. **数据库**：加列。第一次正式发布之前，直接改组件的建表迁移并重建开发库；发布之后只加新的迁移文件（`NNNN_<名字>.up.sql`），扩展与收缩分开发（[协议 14 的结构迁移与版本兼容](../06-protocols/14-data-foundations.md#结构迁移与版本兼容)）。现在按新设计重建的组件都还在开发阶段（`3.0.x`）；从开发进入正式时升 `Y`，并在发布说明里写明（[开发流程与发布的版本](10-development-workflow.md#版本)）。金额、数量、汇率、时间的列按[协议 14](../06-protocols/14-data-foundations.md#金额数量汇率与单位) 的类型。
3. **代码**：记录的类型、读取的列与扫描、写入的 SQL（新建与修改各一处手写的列表）、“有没有变化”的比较、请求的校验（代码地图里“记录”与“模块”所在的文件）。照一个已有的同类字段搜一遍，就能找全要改的位置。
4. **契约**：OpenAPI 的请求与响应、事件的 schema（完整状态事件要带上新字段；两者都是 `additionalProperties: false`，不写进去的字段会被拒绝或校验失败）、proto；只追加，新字段对旧的调用方与消费者可选（[协议 19 的版本与产物](../06-protocols/19-config-secrets-registries-release.md#版本与产物)、[原有决定 0302](../02-decisions/10-earlier-decisions.md#0302-契约只做加法从新版本发布之后约束)）。改了契约就重新生成，并发布契约模块的新标签。
5. **权限**：资源定义里的字段是显式的列表，没列出的字段不输出：新字段加进去；要按角色隐藏的登记为受限字段（[安全 09a](../06-protocols/security/09a-encoding-and-records.md)）。
6. **下游**：投影只保存自己声明的字段，加字段不强迫消费者改；要用它的消费者自己升级（[协议 02](../06-protocols/02-projections.md)）。
7. **种子**：一部分演示数据带上新字段（[种子与测试数据](07-seed-and-test-data.md)）。

## 加一个用户面接口

1. **契约先写**：`contract/openapi.yaml` 加路径，写 `x-operation`（权限键）、请求与响应、错误；有副作用的命令声明是否要求 `Idempotency-Key`。
2. **资源定义**：在组件定义里登记操作（权限键、资源类型、用途、风险、副作用、是否审计）；新的权限键按[协议 19 的注册表](../06-protocols/19-config-secrets-registries-release.md#注册表)命名（[安全 06 的资源、动作与副作用声明](../06-protocols/security/06-security-contracts-and-capabilities.md#资源动作与副作用声明)）。
3. **路由**：在模块的路由注册里加一条，带上操作键；没有操作定义的路由没有授权检查（[组件实现约定的权限与资源](06-component-implementation.md#权限与资源)）。
4. **处理函数的顺序**：校验参数 → 授权目标 → 认领幂等键 → 检查状态 → 在一个事务里写入、写发件表与审计（[原有决定 0507](../02-decisions/10-earlier-decisions.md#0507-幂等键按调用方划分命名空间并绑定到命令)）。事务里不发网络调用。
5. **列表接口**：游标分页、白名单的排序与筛选、数据范围在 SQL 里（[协议 14 的列表](../06-protocols/14-data-foundations.md#列表游标排序与筛选)、[安全 07](../06-protocols/security/07-finite-expressions-containment-and-queries.md)）。
6. **测试**：契约测试核对路由与 OpenAPI 一致；授权的反例（没有权限答 403，看不见答 404）。
7. `BRICKKIT.md` 的契约索引写上新接口与权限键。

## 加或改一个事件

1. **先定事件的种类**：完整状态（可覆盖的投影来源）还是不可遗漏的增量事实（[事务与消息的事件分类](../04-foundations/03-transactions-and-messaging.md#事件分类重放与去重寿命)）；种类决定消费者怎样去重与补取。
2. **契约**：`contract/events/<事件类型>.schema.json`；类型名 `<领域>.<聚合>.<动作>.v<n>`。破坏性变化换新的类型名（`.v2`）并排发布，不改旧的（[协议 19 的版本与产物](../06-protocols/19-config-secrets-registries-release.md#版本与产物)）。
3. **`component.yaml` 的 `events.publishes`** 列上它；订阅方在自己的 `events.subscribes` 列上（项目的[组件索引](../00-overview/09-component-index.md#事件)与 `brickkit deps` 由此得出谁订阅谁）。
4. **发出**：业务变更与发件表在同一个事务（[协议 02](../06-protocols/02-projections.md)）；流与分区在组件定义里，分区数发布后不改。
5. **改载荷之前先看谁受影响**：订阅者在组件索引的事件一节；完整状态事件的载荷通常也是来源方法（`SourceService`）返回的数据，经来源方法读它的依赖方同样受影响，看组件索引的“被谁必需依赖”，并在它们的代码里搜聚合名（例如 `AGGREGATE_LEGAL_ENTITY`）；还没重建的组件看边界卡与协议。

## 调用别的组件，或用别的组件的数据

1. **先问需要的是什么**：要此刻可用的证据（新单据引用客户、产品）→ 同步调用属主的资格查询（[协议 07 的资格引用的提交检查](../06-protocols/07-references.md#资格引用的提交检查)）；要显示或报表用的数据 → 投影（[协议 02 的什么时候可以用投影](../06-protocols/02-projections.md#什么时候可以用投影)）；要对方做一件事 → 系统命令。
2. **只经契约**：引入被调方发布的契约模块；不导入代码，不读写别人的表（[组件实现约定的调用其他组件](06-component-implementation.md#调用其他组件)）。
3. **在事务之外调用**：先取证或先调用，再在本地事务里写；证据有有效期（协议 07 的 W）。
4. **依赖声明**：`component.yaml` 的 `dependencies` 写精确版本；可选依赖写清缺席时本组件怎样降级（边界卡、`BRICKKIT.md` 的依赖说明）。
5. **对方不可达**：答“依赖不可用”，不当作“不存在”。
6. **替用户读**走用户面并转发用户凭据；系统面的结果放进用户响应前先按用户的读取契约裁剪。

## 加一张表

1. 写进组件的 `docs/design.md`（拥有的数据：表、终态、分区与保留），再写迁移。
2. 迁移是纯 SQL，不建角色、不授权、不建 schema、不写 `SET`（[协议 14 的结构迁移与版本兼容](../06-protocols/14-data-foundations.md#结构迁移与版本兼容)）；身份、单号、时间、金额的列按[协议 14](../06-protocols/14-data-foundations.md)。
3. 当队列用的表原子认领；去重表不分区（[协议 01](../06-protocols/01-background-work.md)、[协议 14 的数据库](../06-protocols/14-data-foundations.md#数据库)）。
4. 要按范围读的表，在资源定义里声明维度与列（[安全 07](../06-protocols/security/07-finite-expressions-containment-and-queries.md)）。

## 新建一个组件

走 `brickkit-component` 技能；布局按[AI 导航的标准布局](05-ai-navigation.md#组件仓库的标准布局与代码地图)；身份、端口、schema 先在 `registry/` 追加（[协议 19 的注册表](../06-protocols/19-config-secrets-registries-release.md#注册表)）；开工前写 `docs/design.md`（[开发流程与发布](10-development-workflow.md)）。
