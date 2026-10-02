[English](../../../en/02-decisions/02-permissions/0202-local-permission-bundle.md) · [中文](0202-local-permission-bundle.md)

# 0202 权限在本地判定：对照 bundle 和投影

**状态**：为 3.0.0 修订（bundle v2，以及直接授予的本地投影）；已决定，随 3.0.0 统一升级落地。

## 决策

每一次访问判定都在组件自己的进程里做，依据两个本地来源：

| 来源 | 装什么 | 怎么来 |
|---|---|---|
| bundle，`GET {AUTHZ_URL}/authz/v2/bundle` | 角色 → 键、档位、维度取值、字段键、天花板、委托、`stale_since` | 每 15 秒一次条件 GET（大多答 `304`），收到 poke 时也拉一次，放进进程内的 map |
| 投影，组件自己 schema 里的 `besdk_authz_acl` | 组件声明的资源类型上的直接授予（共享、关系） | 拉取 provider 的变更流，每 5 秒一次，收到 poke 时也拉 |

权限检查是在 bundle 里查一下；列表是一条静态参数化 SQL 谓词，作用在组件自己的行和它的投影上（[0206](0206-no-row-level-security.md)）。请求只在两种情况下才会到达 authz provider：声明为 `derivation: graph` 的资源类型；单条读取所带的一致性令牌领先于投影时。任何组件都不持有权限表或角色副本。SDK 的路由注册把权限键作为必填参数；`make gates` 拒绝用框架原生方法注册的路由。

## 理由

这是标准的本地决策点形态（OPA、Istio）：判定在内存里或在组件自己的库里完成，热路径上没有网络跳。每个请求都去问授权服务，就是每个请求都多一次网络调用，每个组件都和 authz 一样慢、一样可用。只物化直接授予、主体一侧（角色、上级部门、委托人）按请求现展开，调一个人的部门改的是 token，不是投影里的行。改动在约 15 秒（bundle）和 5 秒（投影）内生效；一致性令牌替写入者补上这段差距。authz 不可达时，继续用最后一份 bundle 和投影；第一份 bundle 到达之前，受保护路由答 `503`，`/healthz` 保持健康。

## 挡下什么

- 业务组件里建角色表或权限表，或用事件把角色同步到各组件
- 除上面两种情况外，每个请求都"问一下 authz 这个用户能不能做 X"
- 把 authz 是否可达放进 `/healthz`：authz 抖一下，外壳里每个成员都会重启
- 用 Redis 缓存权限（[0201](0201-no-redis.md)）；跨请求缓存判定结果
- 把 Zanzibar 式的服务（SpiceDB、OpenFGA）作为业务组件的直接依赖或放在热路径上；OpenFGA 可以藏在一个槽位成员后面（[0209](0209-authz-is-a-slot-family.md)）
- 用框架原生的 `GET` / `POST` 注册路由，而不是带权限键的版本

## 何时重新讨论

bundle 已无法轻松放进每个进程的内存，或者某个需求要求改动生效的速度快于轮询间隔加 poke 所能达到的程度时。

完整分析：[20-authorization-provider.md，选择](../../04-foundations/20-authorization-provider.md#选择)。
