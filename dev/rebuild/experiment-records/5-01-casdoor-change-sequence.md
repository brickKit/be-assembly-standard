# 5-01 Casdoor 给不出可靠的变更序号

## 1. 结论

- **Casdoor 4.1.0 没有可以当作变更序号的东西**。按安全 03，`infra/iam-casdoor` 作为外部来源声明（`D_source`）。授权侧的正确性靠定期的全量状态比较（账号的停用状态与更新时间，`P_pull` 起始 1 分钟）；webhook 与操作记录只用来更快地发现变化。
- 依据有三条：
  - **操作记录写的是请求，不是变更**：失败的请求也写，状态是 `error`。
  - **webhook 不带序号**：负载里的 `id` 一律是 0，`name` 是随机 UUID。
  - **webhook 是轮询批量发出的**：约每 30 秒一批，按秒级的发生时刻排序，同一秒内的先后不保证。
- **边界卡已改**：“待代表部署实验核实”换成上面的结论（`docs/zh/07-components/infra.md`）。

## 2. 怎样测的

2026-10-19，本机 `be-casdoor`（`casbin/casdoor:4.1.0`，`logPostOnly = true`），组织 `brickkit`。脚本 `scratchpad/casdoor-repro/repro.sh`：
1. 经 API 以管理员登录。
2. 注册一个 webhook，指向同一网络里的一个监听容器，订阅 `add-user`、`update-user`、`delete-user`。
3. 建一个测试用户，再把它改为停用（`isForbidden = true`）。
4. 读 `casdoor.record` 的新行，看监听容器收到什么。

测完删掉了测试用户与 webhook。

## 3. 看到了什么

| 项 | 观察 |
| --- | --- |
| 操作记录 | 停用请求返回后 100 ms 内，`record` 里有一行 `update-user`，自增编号 3505。失败的请求同样写一行：第一次的停用请求因请求体为空而失败，仍然留下 `update-user` 一行，响应是 `status:"error"` |
| webhook 的负载 | 整条操作记录的 JSON：`action`、`requestUri`、`createdTime`（秒）、`response`、请求体与操作者。**`id` 是 0**，`name` 是随机 UUID，没有可比较的序号 |
| webhook 的时机 | 19:32:22 的停用在 19:32:26 送到，19:32:52 的停用在 19:32:56 送到；送达集中在每分钟的 :26 与 :56 前后，约 30 秒一批，同一批按 `createdTime` 排序 |
| 失败的请求 | 也照常送达（`response` 是 `status:"error"`），消费者必须自己按响应判断变更是否发生 |
| 发不出去的 webhook | 每次重试都在 `record` 里加一行 `send-webhook`（一次停用之后出现了 8 行） |

**顺带清理**：开发环境的 Casdoor 里有一个旧的 webhook `admin/brickkit-user-events`，指向已退役的 2.0.0 适配组件，一直在失败重试。已停用（`is_enabled = false`），没有删除，可以原样恢复。

## 4. 对设计的影响

- **授权侧的新鲜度上界**：`D_source` 取全量比较的间隔加处理时间；webhook 只能缩短发现的时间，不能作为“已同步到某个位置”的证据。
- **适配组件的停用记录**：以自己记录的停用为准（边界卡已写）。Casdoor 一侧只有秒级的更新时间，比较“晚于本地记录的启用类变更”时，同一秒内的先后无法判断，按“未晚于”处理（保守：保持停用并告警）。
- **第 5 步的范围**：只做到令牌、公钥与换取入口，补取与水位回声留到底层阶段；这里的结论先写进边界卡，实现随那一阶段。
