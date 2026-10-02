[English](../../../en/02-decisions/05-runtime/0508-background-work-only-through-jobs.md) · [中文](0508-background-work-only-through-jobs.md)

# 0508 后台工作只经 SDK 的 Jobs

**状态**：已决定，随 3.0.0 统一升级落地。

## 决策

组件里每一项不由请求触发的工作，都在模块里的同一处声明为 SDK Jobs 端口的四种之一，或声明为一个 reconciler，由 SDK 运行和监督：

| 种类 | 语义 | 状态（在组件自己的 schema 里） |
|---|---|---|
| `every` | 每个副本都跑；工作用 `SKIP LOCKED` 认领 | — |
| `singleton` | 所有副本中同一时刻至多一个在跑，靠租约（TTL 30 s，每过三分之一续约），以 epoch 作防护令牌 | `besdk_job_lease` |
| `cron` | 每个时间槽在所有副本中只跑一次，用 `INSERT … ON CONFLICT DO NOTHING` 抢槽；按 `BUSINESS_TIMEZONE` 求值，除非任务指定了自己的时区 | `besdk_job_slot` |
| `queue` | 在业务事务里入队，提交后至少执行一次，按退避重试，用尽后交给它的 `OnDead` handler | `besdk_job_queue` |
| reconciler | 扫描处于非终态且已过期的行，逐行以租约认领，推进它，或放弃并转为 `SUSPENDED`、开一个异常待办 | `besdk_reconcile` |

- 模块的启动钩子只做一次性初始化，从不启动循环。
- 失败或 panic 的任务被记日志、计数，并按退避重启；一个任务结束从不让另一个停下；单跑和外壳行为一致。
- 每次运行都有超时；任务指标使用 `be_job_*`、`be_queue_*`、`be_reconcile_*` 这些名字。
- 不用 Kubernetes CronJob，不用 `pg_cron`，不用外部调度器。

## 理由

3.0.0 之前，十二个组件各带一份手抄的循环，各自一个 ticker；在外壳里，某个成员的循环失败后就一直停着，而单跑时进程会退出并被重启。一个监督器加三张表，在两种形态下、在每门语言里行为一致，多副本时也不需要领导者就能保持正确。在业务事务里入队，意味着异步命令当且仅当业务写入提交时才存在（[0501](0501-no-network-inside-a-transaction.md)）。

## 挡下什么

- 模块代码里的 ticker、goroutine、线程、`setInterval` 或 sleep 循环（门禁 `module-ticker-scan`）
- 从启动钩子里启动循环
- "提交后在后台调一下"却没有队列行
- 用外部调度器或数据库扩展来跑组件的任务
- 没有超时的任务，或失败后会让进程或其他任务停下的任务

## 何时重新讨论

经测量的任务量超过 PostgreSQL 能承受的程度（每秒数千个任务：入队任务改走总线），或出现第一个跨多人、多天的长流程（评估工作流引擎，先 DBOS，后 Temporal）时。

完整分析：[19-background-jobs.md，选择](../../04-foundations/19-background-jobs.md#选择)。
