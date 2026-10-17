# 0-06 本机进程与 Podman 混合（无根 Podman，`target: podman`）

## 1. 结论

**通过**。同一个项目在 `target: podman` 下三种布局都能跑通：全部在 Podman 容器（P 行）；外壳在容器、单跑的组件是本机进程；外壳是本机进程、单跑的组件在容器。两个方向的调用都通：

- 本机进程调容器：经发布到宿主机的 10000 + 容器端口（18081、18082、18091）。
- 容器调本机进程：经 `extra_hosts: <服务名>:host-gateway`；无根 Podman（pasta）把 `host-gateway` 解析成 `169.254.1.2`，能到达宿主机上监听通配地址的进程。

基础资源也在 Podman 里：容器经 `host.docker.internal:<宿主机端口>`、本机进程经改写后的 `localhost:<宿主机端口>` 都连得上。迁移按“代码在哪里跑，迁移就在哪里跑”：容器组件与容器外壳的成员用镜像迁移；本机进程与本机外壳的成员用 `local.migrationCommand` 从源码迁移。没有发现 BrickKit 的问题。

## 2. 测了什么、为什么

计划第 0 步：“本机进程与 Podman 混合”，对应 LP 行；同时是这台机器上第一次用 `target: podman`，顺带验证 P 行的基本形态。要确认：无根 Podman 下容器能否到达宿主机上的本机进程（Docker 下 0-05 已验证）；本机进程能否到达容器；基础资源放在 Podman 时地址是否照常；构建、迁移、崩溃、`status`、`down` 在 Podman 下的表现。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| BrickKit | CLI v1.7.1 |
| Podman | 5.7.0，无根，网络 netavark，pasta 0.0~git20260120；`podman compose` 借用 docker-compose v5.3.1 插件 |
| 基础资源 | Podman 里另起 `postgres:16-alpine`（宿主机 25432）与 `nats:2.10-alpine`（24222）；部署文件的 `vars:` 把 `PG_PORT`、`NATS_URL` 指过去，`PG_HOST` 仍是 `host.docker.internal` |
| 桩项目 | 0-05 的同一组组件（Go 外壳承载 alpha、beta；gamma；Python 外壳承载 pyr；delta），另加：Go 成员的 `cmd/server` 认 `migrate`；alpha 与 gamma 都写 `migration.command`（镜像）与 `local.migrationCommand`（源码）；Python 外壳像 Go 外壳的 `vendor` 一样，把成员模块复制进自己的 `vendor/`，从源码运行时仍从成员目录导入 |

## 4. 怎样跑

`r006-setup.sh` 生成项目，`run006.sh` 依次做四部分：

1. 全部在容器：`brickkit build`（构建进 Podman）、`up`，在容器里调两条链、查基础资源，看迁移容器；`status`、`down`。
2. 两个外壳在容器，gamma、delta 是本机进程。
3. 两个外壳是本机进程，gamma、delta 在容器。
4. 接着第 3 部分，`kill -9` 本机 Go 外壳。

## 5. 结果

| 步 | 结果 |
| --- | --- |
| `build` | 7 个镜像都进了 Podman（`localhost/demo-*`）：Go 17–18 MB，Python 54 MB；成员也各有自己的镜像 |
| 全部在容器，`up` | 4 个容器 healthy；alpha（外壳成员）与 gamma 的迁移容器先跑、以 0 退出，拿到 `PG_HOST=host.docker.internal`、`PG_PORT=25432` |
| 全部在容器，调用 | gamma → beta → alpha（经外壳的网络别名）通；delta → alpha 与 pyr 通；基础资源经 `host.docker.internal:25432`、`:24222` 连通 |
| `status`、`down` | `status` 列出 7 个组件（成员标“in shell”）；`down` 停掉全部容器 |
| 外壳在容器、gamma 与 delta 是本机进程 | 外壳容器把成员端口发布为 18081、18082、18091；gamma 拿到 `DEMO_BETA_ENDPOINT=http://localhost:18082`、`PG_PORT=25432`；gamma 先从源码迁移（`PG_HOST=localhost`）再启动；两条链与基础资源都通。冷编译到两个本机进程就绪 12.9 s |
| 外壳是本机进程、gamma 与 delta 在容器 | 容器的 `/etc/hosts` 里 `demo-shell-0-1-0`、`host.docker.internal`、`host.containers.internal` 都是 `169.254.1.2`；gamma（容器）→ beta（本机外壳）→ alpha 通；delta（容器）→ alpha 与 pyr（两个本机外壳）通；alpha 从源码迁移、gamma 用镜像迁移。冷编译到本机外壳就绪 11.6 s |
| 本机 Go 外壳被 `kill -9` | 本机进程全部停止，`up` 退出码 1，列出崩溃；Podman 容器照常运行，gamma 的调用返回 502；`status` 只列两个容器；`down` 停掉它们 |

前两次尝试因桩代码失败，修好后才得到上面的结果（原始数据开头有说明）：一是 `demo/pyr` 写了 `deployment.build` 却没有 `Dockerfile`；二是 Python 外壳的镜像里没有成员模块，容器启动即退出。

## 6. 观察与异常

- **无根 Podman 的 `host-gateway` 可用**。pasta 把它映射到 `169.254.1.2`，容器经它到达宿主机上监听 `0.0.0.0` 的本机进程，以及 Podman 发布在宿主机上的基础资源端口。BrickKit 生成的 compose 在 Docker 与 Podman 下一字不差，不需要按引擎改配置。
- **`brickkit build` 遇到第一个失败就停**（第一次尝试：alpha、beta 建好，pyr 失败，其余没有构建）。`up` 的镜像检查会一次列全缺的镜像，所以修好后再 `build` 即可；不反馈。
- **`up` 失败后，已经启动的容器留着**（第二次尝试：Python 外壳反复退出，`up` 报 `ENGINE_FAILED`，Go 外壳与 gamma 仍在运行，要 `down`）。与 compose 的行为一致；实验脚本在每次失败后 `down`。
- **Python 外壳的镜像要带上成员代码**。Go 外壳靠 `go mod vendor`；Python 外壳需要等价的做法（第 3 步按包安装定下，这里复制模块代替）。从源码运行时外壳仍从成员目录导入，两种形态的代码来源与“代码在哪里跑，迁移就在哪里跑”一致。
- **混合时容器先于本机进程启动**（与 0-05 相同）；`podman compose` 每次打印一行“Executing external compose provider”的提示，不影响结果。

## 7. 影响

- **计划**：P 行与 LP 行的机制成立，不需要改。基础资源放在 Podman 时，端口与 Docker 那套错开（本次 25432、24222），由部署文件的 `vars:` 指向；正式跑 P、LP 行时，基础资源只起 Podman 那一套（`make up` 的 Docker 那套先停），端口用回 5432、4222。
- **第 3 步的 Python 外壳**：外壳镜像怎样带上成员代码（安装成员包，或像 Go 一样复制），与“从源码运行时用成员目录”一起定下。
- 不需要改设计。

## 8. 原始数据

`dev/rebuild/experiment-data/0-06/run1.txt`（含 `run006.sh` 与生成脚本 `r006-setup.sh`）
