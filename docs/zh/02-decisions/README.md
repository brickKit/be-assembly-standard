[English](../../en/02-decisions/README.md) · [中文](README.md)

# 决策

约束本项目后续改动的决策。每个文件写明结论、简短理由、会被它挡下的需求，以及在什么情况下值得重新讨论。需求与其中某条冲突时，既不悄悄拒绝，也不悄悄照做：引用那条决策，交给人来决定。

## 编号

- 每个文件夹有自己的编号段，所以同一文件夹里的编号始终连续：`01-architecture/` 0101–0199，`02-permissions/` 0201–0299，`03-contracts-and-data/` 0301–0399，`04-frontend/` 0401–0499。新增的文件夹 `NN-…` 用 `NN01`–`NN99`。
- 新决策取所在文件夹编号段里下一个空闲编号。
- 编号一经分配不复用，因为其他文档按编号引用。
- 被推翻的决策保留原文件，在顶部加一行 `Superseded by NNNN`，新决策反向链接到它。
- 阶段 06 结束之前，阶段 06 里写下或改过的决策直接原地改写、保留编号：下游还没有任何东西依赖它。阶段 06 结束之后适用上一条。

## 文件夹

| 文件夹 | 放什么 |
|---|---|
| `01-architecture/` | 系统怎么切分、怎么组装：组件边界、schema、锁定的技术栈、槽位族、语言、哪些不是组件、共享地址、外壳 |
| `02-permissions/` | 谁能做什么、能看到哪些行：不用 Redis、本地权限 bundle、只承载身份的 token、纯并集、数据范围、不用行级安全 |
| `03-contracts-and-data/` | 什么跨越边界、什么写进数据库：金额与分页、契约只做加法、迁移里不放测试账号 |
| `04-frontend/` | 前端技术栈、ui-kit、导航、用户偏好、设计令牌 |

新决策放进它所回答的问题对应的文件夹；都不合适时，在 `docs/en/02-decisions/` 和 `docs/zh/02-decisions/` 里同时新增一个带编号的文件夹。

## 索引

| 编号 | 决策 | 挡下什么 | 文件夹 |
|---|---|---|---|
| [0101](01-architecture/0101-no-imports-between-components.md) | 组件之间禁止 import，只共享 `be-sdk-*` 和生成的契约包 | 因为同在一个外壳就直接调用对方的函数；公共 model 包 | `01-architecture/` |
| [0102](01-architecture/0102-one-schema-per-component.md) | 一个数据库，每个组件一个 schema 和一个角色，迁移状态表放在自己的 schema | 每个组件一个数据库；跨 schema JOIN；直接读别的组件的表 | `01-architecture/` |
| [0103](01-architecture/0103-locked-stack-per-language.md) | 每种语言的技术栈逐格锁定（Gin / FastAPI，不用 ORM，迁移工具固定） | Echo、GORM、Flask、alembic、gunicorn 多 worker；组件自选框架 | `01-architecture/` |
| [0104](01-architecture/0104-variants-become-slot-families.md) | 槽位族需要多种合理实现，**并且**该位置没有依赖边；否则是一种默认实现加客户 Fork | 成本核算 / 拣货槽位族（"让客户选先进先出还是移动加权平均成本" → 默认实现 + Fork）；按客户堆 `if costingMethod == ...`；"把算法做成可配置" | `01-architecture/` |
| [0105](01-architecture/0105-no-java-or-csharp.md) | 不用 Java / C# | Spring Boot / .NET 组件；第四种后端语言 | `01-architecture/` |
| [0106](01-architecture/0106-infrastructure-is-not-a-component.md) | 事件总线、对象存储、网关、可观测性不是组件 | `infra/nats` 或网关组件；改一个设置就把 NATS 换成 Kafka | `01-architecture/` |
| [0107](01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md) | 拉权限 bundle 和验证 token 用共享变量，不建依赖；真正通过 gRPC 调用 authz / iam 的照常声明依赖 | 只为拉 bundle 或验 token 就对 `infra/authz` 或 IAM 组件建依赖边；不声明依赖就调用它们的 gRPC 接口 | `01-architecture/` |
| [0108](01-architecture/0108-one-repository-per-shell.md) | 一个外壳、一个仓库（以子模块挂在 `shell/<scope>/<name>/`，在那里发布，tag 是裸 `<版本>`）、一个镜像、一份成员清单 | 把外壳代码提交在本仓库；在本仓库发布外壳；外壳里写逻辑；只升成员不升外壳 | `01-architecture/` |
| [0201](02-permissions/0201-no-redis.md) | 不引入 Redis | 加缓存、用 Redis 缓存权限、Redis 存会话、分布式锁、Redis 限流 | `02-permissions/` |
| [0202](02-permissions/0202-local-permission-bundle.md) | 权限判定基于拉进内存的 bundle | 组件里建权限表；用 Redis 缓存权限；每个请求都问 authz；把 authz 放进 `/healthz` | `02-permissions/` |
| [0203](02-permissions/0203-jwt-carries-identity-only.md) | token 只承载身份 | 把权限或 scope 塞进 JWT claims | `02-permissions/` |
| [0204](02-permissions/0204-permissions-are-a-pure-union.md) | 权限是纯并集，没有 Deny | "除了某人以外所有人"；拒绝规则；规则优先级 | `02-permissions/` |
| [0205](02-permissions/0205-data-scopes-ship-with-the-version.md) | 数据范围随版本发布；`data_scopes` 必填 | 管理行可见性的后台界面；查完再过滤；省略 `data_scopes` | `02-permissions/` |
| [0206](02-permissions/0206-no-row-level-security.md) | 不用行级安全，不做共享引擎；`org` 维用 `dept_path` 前缀 | `CREATE POLICY`；记录共享表；组织树副本 | `02-permissions/` |
| [0301](03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md) | 金额是字符串编码的十进制；列表按游标分页 | `double` 金额；`List` 里的 `offset` / 页码 | `03-contracts-and-data/` |
| [0302](03-contracts-and-data/0302-contracts-are-additive-only.md) | 契约只做加法 | 改名、改类型、删除字段、RPC 或事件 subject | `03-contracts-and-data/` |
| [0303](03-contracts-and-data/0303-no-test-accounts-in-migrations.md) | 测试账号不写进迁移；首个管理员来自 `BOOTSTRAP_ADMIN_SUB` | 默认管理员账号；迁移里放演示数据 | `03-contracts-and-data/` |
| [0401](04-frontend/0401-frontend-stack.md) | Vue 3；PC 用 AntDV + vxe-table；移动端用 wot-design-uni；只共享设计令牌 | React；Element Plus / Naive UI；两端共用一套组件库 | `04-frontend/` |
| [0402](04-frontend/0402-third-party-ui-only-in-ui-kit.md) | 第三方 UI 组件只能出现在 ui-kit 中 | 页面里直接 import AntDV / vxe；为了好看混搭组件库 | `04-frontend/` |
| [0403](04-frontend/0403-two-tier-navigation.md) | PC 端采用控制台式两层导航，带应用内标签页 | 多级树形菜单；把 admin 模板当依赖；从空白 `<div>` 搭页面 | `04-frontend/` |
| [0404](04-frontend/0404-four-user-preferences.md) | 用户偏好只有四项 | 布局模式切换；每个用户自选主题色 | `04-frontend/` |
| [0405](04-frontend/0405-design-tokens-are-css-variables.md) | 设计令牌是运行时 CSS 变量 | 令牌写成 TS 常量；硬编码颜色和间距 | `04-frontend/` |
