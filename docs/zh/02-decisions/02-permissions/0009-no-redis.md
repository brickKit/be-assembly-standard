[English](../../../en/02-decisions/02-permissions/0009-no-redis.md) · [中文](0009-no-redis.md)

# 0009 不引入 Redis

## 决策

本项目不运行 Redis，也不运行其他缓存服务。

## 理由

通常引入 Redis 要解决的问题都已有着落：身份是无状态的 JWT，权限是进程内的 map（[0010](0010-local-permission-bundle.md)），别的组件拥有的数据以本地摘要保存、由事件刷新，并发控制用 PostgreSQL 行锁，限流归网关。客户在一台资源有限的机器上部署，每多一个基础服务，就多一样要安装、备份、加固和监控的东西。

## 挡下什么

- "加一层缓存" / "在这个查询前面放个 Redis"
- 会话或 refresh token 存进 Redis
- 用 Redis 做分布式锁、计数器或流水号
- 用 Redis 缓存权限或 bundle——比它要替代的进程内 map 更慢
- 应用代码里基于 Redis 做限流
- 把 Redis 当消息队列（事件走 NATS）

## 何时重新讨论

有一个实测的负载，PostgreSQL 加进程内内存确实撑不住，并且把数字写了下来——而且涉及的不止一个组件。
