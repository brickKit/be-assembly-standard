# 0-09 同一组件两个副本

## 1. 结论

**通过（v1.8.0 起三种目标都支持副本）**。K8s 下 `replicas: 2` 对单跑组件与外壳都有效：两个 Pod、自动生成 PodDisruptionBudget（`maxUnavailable: 1`）、外壳成员的 Service 有两个端点、迁移 Job 仍只跑一次；删掉一个副本时 Service 照常应答，Deployment 补回副本；改回 1 个副本时 `up` 清掉 PDB。

第一次（v1.7.2）Docker、Podman 下 `replicas` 被忽略，套件 E 的多副本格一度改到 K8s 两格，并写了功能请求 FRR-006。BrickKit 在 v1.8.0 实现：Docker 下生成 compose 的 `deploy.replicas`，服务名解析到每个副本，迁移仍只跑一次，`status` 带就绪数；多个副本不能映射宿主机端口时报 `PORT_CONFLICT`。复测通过（第 9 节），套件 E 恢复四格。compose 没有滚动升级：换镜像时副本一起重建，所以单机多副本用于验证多实例行为，不是不停机升级。

## 2. 测了什么、为什么

计划第 0 步：“同一组件两个副本”，对应套件 E 的 E1–E4（发件表只发一次、工作项只被一个副本认领、并发与接管）。这里只验证部署层：副本能不能起来、流量怎样分到副本、迁移是否只跑一次、副本消失时是否中断。并发正确性本身要等 SDK（第 2 步）有发件表与认领之后在套件 E 里测。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| BrickKit | CLI v1.7.2 |
| 集群 | minikube v1.38.1（Kubernetes v1.35.1，Calico）；基础资源在命名空间 `r007-base` |
| 项目 | 0-07 的项目；delta（单跑）与 Go 外壳（alpha、beta）写 `replicas: 2` |

## 4. 怎样跑

`run009.sh`：K8s 下 `up`，看清单、Pod、PDB、EndpointSlice 与迁移 Job；删掉一个 delta 副本和一个外壳副本，同时从 gamma 的 Pod 持续调用 15 s；改回 1 个副本再 `up`；然后 `target: docker` 写同样的 `replicas`。第一次运行有三处脚本问题（见第 6 节），`run009b.sh` 重做调用与删除。

## 5. 结果

| 步 | 结果 |
| --- | --- |
| 清单 | 多出 `poddisruptionbudgets/` 目录，delta 与外壳各一份；迁移仍是 alpha、gamma 各一个 Job |
| `up` | delta、外壳各 2/2；PDB `MAX UNAVAILABLE 1`；两个迁移 Job 各完成 1 次 |
| 端点 | `demo-alpha-0-1-0`、`demo-beta-0-1-0`、`demo-shell-0-1-0` 三个 Service 都是外壳的两个 Pod；`demo-delta-0-1-0` 是 delta 的两个 Pod |
| 调用（run 1b） | `up` 之后立即连续调用 gamma 的链路 5 次，全部正常 |
| 删掉一个副本时持续调用 15 s | 到 delta（单跑）69 次全部成功；到外壳里的 alpha 64 次失败 1 次；两个 Deployment 都在约 12 s 内补回副本 |
| 改回 1 个副本 | `up` 报“清掉旧版本的遗留”：两个 PDB 被删除；Deployment 回到 1/1 |
| Docker 下 `replicas: 2` | `lint` 与 `up --dry-run` 警告“replicas has no effect with target: docker and is ignored”，点名 delta 与外壳；生成的 compose 里没有副本 |

## 6. 观察与异常

- **删副本时那 1 次失败**：桩外壳收到 SIGTERM 就退出，不先摘掉就绪、也不排空在途连接；正在终止的 Pod 从端点里摘掉之前，还会有请求打到它。真正的组件要靠 SDK 的体面停止（先报未就绪、等端点摘除、再关闭监听），第 2 步的 SDK 验收要包括“删掉一个副本时持续调用，零失败”。
- **第一次运行的三处脚本问题**（原始数据开头有说明）：基础资源的命名空间还在删除中（0-07 用了 `--wait=false`），PostgreSQL 与 NATS 没建上（桩组件的调用不依赖它们）；0-07 留下的 `deploy.local.yaml` 里有 `mode: debug`，`lint` 报错（本地模式虽然关着，`lint --all` 仍会校验这个文件）；探测 delta 用了它不提供的路径。
- **第一次运行里 gamma 的链路超时过一次，没有复现**。当时集群里的 `demo-gamma:0.1.0` 是 0-08 项目构建的同名镜像（代码不同）；重新构建、load 之后连续 5 次都通。原因没有查明；实验项目之间用了相同的组件 ID 与版本、镜像名相撞，是这类问题的来源，正式实验每个格子的组件版本各不相同（不重用版本号，A110），不会再撞。
- 迁移在多副本时只跑一次（独立的 Job），与副本数无关，符合 BrickKit 文档（“不用 InitContainer，避免多副本并发迁移”）。

## 7. 影响

- **计划（套件 E）**：v1.7.2 时 E1–E4 一度只在 K8s 两格跑；v1.8.0 起 Docker、Podman 支持副本，E1–E4 恢复在四格跑（D·S、D·H、K·S、K·X）。
- **第 2 步 SDK**：体面停止要做到删副本时零失败；作为验收项。
- 不需要改设计。

## 8. 原始数据

`dev/rebuild/experiment-data/0-09/run1.txt`（v1.7.2；含 `run009.sh`、`run009b.sh`；项目与生成脚本见 0-07）；`run2.txt`（v1.8.0 的 Docker 复测，含 `run009-2.sh`）

## 9. v1.8.0 复测：Docker 下的副本（2026-10-17）

| 步 | 结果 |
| --- | --- |
| delta 与 Go 外壳写 `replicas: 2`，`lint`、`up` | 不再警告；compose 里两处 `deploy.replicas: 2`；`up` 报“running (healthy), 2/2 replicas ready”；每个各两个容器 |
| 服务名 | gamma 里 `nslookup demo-delta-0-1-0`、`demo-alpha-0-1-0`（外壳成员）各解析出两个地址；调用链正常 |
| `status` | 每个组件一行，带“2/2 replicas ready”，外壳成员同样 |
| 停掉 delta 与外壳各一个副本，gamma 持续调用 12 s | 两条调用各 56 次，全部成功；`status` 把它们列进“未在运行”，“1/2 replicas ready”，状态取最差的副本 |
| 多副本加 `expose` | `--dry-run` 报 `PORT_CONFLICT`，建议改 `replicas: 1` 或去掉 `expose` |
| 外壳多副本、调用方是本机进程（gamma `mode: local`） | `--dry-run` 报 `PORT_CONFLICT`（外壳要映射 18082），建议在这次读的部署文件里改 `replicas: 1` 或把调用方也放进容器 |

**观察**：被停掉的 Python 副本退出码 137（宽限期过后被强杀）：Python 作为容器的 1 号进程，没装信号处理就不响应 SIGTERM；Go 的退出码 2。第 3 步的 Python SDK 要自己处理 SIGTERM 并体面停止（与第 6 节对 Go 的要求相同）。

**结论**：通过，FRR-006 关闭。复测前要先 `build --force`：0-08 的脚本删过本机的 `demo-*` 镜像，剩下的同名标签有的是 0-08 项目的代码（实验项目之间同一 ID 与版本的镜像相撞，正式实验不会出现，见第 6 节）。
