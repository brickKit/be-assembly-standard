[English](README.md) · [中文](README.zh.md)

# 决策

约束本项目后续改动的决策。每个文件写明结论、简短理由、会被它挡下的需求，以及在什么情况下值得重新讨论。需求与其中某条冲突时，既不悄悄拒绝，也不悄悄照做：引用那条决策，交给人来决定。

## 编号

- 编号从 `0001` 开始，一经分配不重排、不复用，因为其他文档按编号引用。
- 新决策取下一个空闲编号。
- 被推翻的决策保留原文件，在顶部加一行 `Superseded by NNNN`，新决策反向链接到它。

## 索引

| 编号 | 决策 | 挡下什么 |
|---|---|---|
| [0001](0001-no-imports-between-components.zh.md) | 组件之间禁止 import，只共享 `be-sdk-*` 和生成的契约包 | 因为同在一个外壳就直接调用对方的函数；公共 model 包 |
| [0002](0002-one-schema-per-component.zh.md) | 一个数据库，每个组件一个 schema 和一个角色，迁移状态表放在自己的 schema | 每个组件一个数据库；跨 schema JOIN；直接读别的组件的表 |
| [0003](0003-locked-stack-per-language.zh.md) | 每种语言的技术栈逐格锁定（Gin / FastAPI，不用 ORM，迁移工具固定） | Echo、GORM、Flask、alembic、gunicorn 多 worker；组件自选框架 |
| [0004](0004-no-redis.zh.md) | 不引入 Redis | 加缓存、Redis 存会话、分布式锁、Redis 限流 |
| [0005](0005-local-permission-bundle.zh.md) | 权限判定基于拉进内存的 bundle | 组件里建权限表；每个请求都问 authz；把 authz 放进 `/healthz` |
| [0006](0006-jwt-carries-identity-only.zh.md) | token 只承载身份 | 把权限或 scope 塞进 JWT claims |
| [0007](0007-permissions-are-a-pure-union.zh.md) | 权限是纯并集，没有 Deny | "除了某人以外所有人"；拒绝规则；规则优先级 |
| [0008](0008-data-scopes-ship-with-the-version.zh.md) | 数据范围随版本发布；`data_scopes` 必填 | 管理行可见性的后台界面；查完再过滤；省略 `data_scopes` |
| [0009](0009-no-row-level-security.zh.md) | 不用行级安全，不做共享引擎；`org` 维用 `dept_path` 前缀 | `CREATE POLICY`；记录共享表；组织树副本 |
| [0010](0010-money-as-strings-lists-by-cursor.zh.md) | 金额是字符串编码的十进制；列表按游标分页 | `double` 金额；`List` 里的 `offset` / 页码 |
| [0011](0011-contracts-are-additive-only.zh.md) | 契约只做加法 | 改名、改类型、删除字段、RPC 或事件 subject |
| [0012](0012-variants-become-slot-families.zh.md) | 多种合理实现并存，是新增槽位族的信号 | `if costingMethod == ...`；"把算法做成可配置" |
| [0013](0013-frontend-stack.zh.md) | Vue 3；PC 用 AntDV + vxe-table；移动端用 wot-design-uni；只共享设计令牌 | React；Element Plus / Naive UI；两端共用一套组件库 |
| [0014](0014-third-party-ui-only-in-ui-kit.zh.md) | 第三方 UI 组件只能出现在 ui-kit 中 | 页面里直接 import AntDV / vxe；为了好看混搭组件库 |
| [0015](0015-two-tier-navigation.zh.md) | PC 端采用控制台式两层导航，带应用内标签页 | 多级树形菜单；把 admin 模板当依赖；从空白 `<div>` 搭页面 |
| [0016](0016-four-user-preferences.zh.md) | 用户偏好只有四项 | 布局模式切换；每个用户自选主题色 |
| [0017](0017-design-tokens-are-css-variables.zh.md) | 设计令牌是运行时 CSS 变量 | 令牌写成 TS 常量；硬编码颜色和间距 |
| [0018](0018-no-java-or-csharp.zh.md) | 不用 Java / C# | Spring Boot / .NET 组件；第四种后端语言 |
| [0019](0019-infrastructure-is-not-a-component.zh.md) | 事件总线、对象存储、网关、可观测性不是组件 | `infra/nats` 或网关组件；改一个设置就把 NATS 换成 Kafka |
| [0020](0020-no-test-accounts-in-migrations.zh.md) | 测试账号不写进迁移；首个管理员来自 `BOOTSTRAP_ADMIN_SUB` | 默认管理员账号；迁移里放演示数据 |
| [0021](0021-authz-and-iam-addresses-are-shared-vars.zh.md) | authz 与 iam 的地址是共享变量，不是依赖 | 对 `infra/authz` 或 IAM 组件建依赖边 |
| [0022](0022-shells-are-project-code.zh.md) | 外壳是项目代码：一个外壳、一个镜像、一份成员清单 | 每个外壳一个仓库；外壳里写逻辑；只升成员不升外壳 |
