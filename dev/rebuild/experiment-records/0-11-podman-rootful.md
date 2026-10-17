# 0-11 Podman 有根与无根

## 1. 结论

**无根通过（0-06）；有根在这台机器上部分通过，被 Docker 的防火墙规则挡住（已证实）**。有根 Podman 下，BrickKit 的构建、迁移、启动、`status`、`down` 都正常，容器经 `host-gateway` 到宿主机上的本机进程也通（外壳为本机进程的布局全部通过）。但全部组件都在有根容器里时，**容器之间、容器到宿主机上映射的端口都超时**，而所有容器 healthy、`status` 全绿。

原因（第二次由用户以 root 执行诊断脚本证实，见第 4 节末）：同一台机器上的 Docker 加载了 `br_netfilter`（`bridge-nf-call-iptables = 1`），网桥上的流量要过 iptables 的 FORWARD 链，Docker 把 FORWARD 的默认策略设为 DROP；netavark 在自己的 `inet netavark` 表里放行也没用，任何一个 forward 钩子上的 DROP 都是最终的。有根 Podman 网桥上的容器间流量、以及 DNAT 回另一个容器的映射端口流量走 FORWARD，被丢掉；到宿主机自己的进程走 INPUT，不受影响。无根 Podman 用用户态网络（pasta），不经过宿主机的 FORWARD 链，所以没受影响。这不是 BrickKit 的问题。

## 2. 测了什么、为什么

计划第 0 步：“Podman 有根与无根”，对应套件 B6（有根对无根的代价）。无根已在 0-06 验证。这里确认有根 Podman 下 BrickKit 的整套流程能跑，以及地址与网络是否照常。有根需要 root，这台机器的 `sudo` 要密码，由用户执行脚本 `run011-rootful.sh`（在 `/tmp/r011-rootful` 里复制 0-06 的桩项目，结束时清理容器与镜像）。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| BrickKit | CLI v1.7.2，由 root 执行 |
| Podman | 5.7.0，`rootless=false`，netavark；`podman compose` 借用 docker-compose 插件 |
| 同机 | Docker 29.7.1（`make up` 的基础资源在它里面）；`br_netfilter` 已加载，`bridge-nf-call-iptables = 1`，`ip_forward = 1` |
| 基础资源 | root 的 Podman 里另起 PostgreSQL（宿主机 35432）与 NATS（34222） |
| 项目 | 0-06 的桩项目，部署文件的 `vars:` 指向上面两个端口 |

## 4. 结果

| 步 | 结果 |
| --- | --- |
| 第一次运行 | `build` 正常（79 s，root 的镜像存储是空的）；`up`、`status`、`down` 都报 `ENGINE_FAILED`：“failed to connect to the docker API at unix:///run/podman/podman.sock”。root 的 `podman.socket` 没有开（disabled、inactive）；用户的 `podman.socket` 一直开着，所以无根正常。BrickKit 的排障文档写了这个前提，但只给了无根的写法（`systemctl --user enable --now podman.socket`） |
| 第二次运行 | 脚本临时 `systemctl start podman.socket`，结束时停掉，恢复原状 |
| 全部在有根容器：`build`、`up` | 构建 20 s；4 个容器 healthy，迁移容器正常；`status` 列出 7 个组件 |
| 全部在有根容器：调用 | gamma → beta（外壳容器）**超时**；delta → alpha、pyr **超时**；delta 连 `host.docker.internal:35432`、`:34222`（宿主机上的映射端口）**超时**。`/etc/hosts` 里 `host.docker.internal` 是网桥网关 `10.89.0.1` |
| 全部在有根容器：内存 | 外壳 1.9 MB、gamma 1.9 MB、Python 外壳 13.3 MB、delta 16.6 MB（`podman stats`） |
| 外壳是本机进程（root），gamma、delta 在有根容器 | 全部通：容器 `/etc/hosts` 把 `demo-beta-0-1-0` 等成员名映射到 `10.89.0.1`；gamma → beta → alpha、delta → alpha 与 pyr 都通；alpha 从源码迁移；本机外壳经 `localhost:35432`、`:34222` 连通基础资源 |
| 清理 | 容器与镜像删除；root 的 `podman.socket` 回到 inactive |
| 诊断（`run011-fw.sh`，用户以 root 执行） | `iptables -S FORWARD`：`-P FORWARD DROP`，只跳 `DOCKER-USER`、`DOCKER-FORWARD`；nft 的 `ip filter` 表 FORWARD `policy drop`，另有 netavark 自己的 `inet netavark` 表。两个临时有根容器之间调用超时，同时 FORWARD 的 DROP 计数从 17 个包涨到 21 个；容器访问自己正常。在 `DOCKER-USER` 里临时放行这个网桥（`-i`、`-o` 各一条 ACCEPT）后同样的调用立即成功；规则删除后 `DOCKER-USER` 恢复为空 |

## 5. 观察

- **通与不通的分界正好是 FORWARD 链**：容器 → 宿主机进程（INPUT）通；容器 → 容器、容器 → 映射端口（DNAT 后转发到另一个容器）不通。诊断的计数与放行对照证实了这一点。
- **绕法**：在 Docker 预留给用户的 `DOCKER-USER` 链里放行 Podman 的网桥（例如 `iptables -I DOCKER-USER -i podman+ -j ACCEPT` 与 `-o podman+`；netavark 新建的网络默认叫 `podman1`、`podman2`……），或干脆不在同一台机器上同时用 Docker 与有根 Podman。前者要持久化防火墙配置，属于主机运维，不是项目或 BrickKit 该做的事。
- **故障是静默的**：健康检查只查进程自己（项目规则），所以 BrickKit 与引擎都报全绿；只有真正调用时才超时。部署后的冒烟测试（调一次每条依赖边）能发现它，正式实验的每一格都应该先跑冒烟测试再量。
- 有根 Podman 自己的机制都正常：`host-gateway` 是网桥网关地址（无根时是 pasta 的 `169.254.1.2`）；成员名经 `extra_hosts` 映射，与 v1.7.2 的地址规则一致。
- 本项目以后不推荐在同一台机器上同时用 Docker 与有根 Podman；给客户的部署说明写明“二选一”。

## 6. 影响

- **计划（已修订）**：套件 B6（有根对无根）要在没有 Docker、或停掉 Docker 并清掉它的转发规则的机器上跑；这台机器上跑之前先确认 FORWARD 链。写进“已知风险”。P 与 LP 两行用无根 Podman，不受影响。
- **实验的每一格**：先跑一次冒烟测试（每条依赖边调一次）再开始测量，避免“全绿却不通”的格子。
- **给客户的部署说明（第 14 步）**：Docker 与有根 Podman 不要装在同一台机器上；用 Podman 时，无根需要用户的 `podman.socket`，有根需要系统的 `podman.socket`。
- 不需要改设计，没有 BrickKit 的问题。

## 7. 原始数据

`dev/rebuild/experiment-data/0-11/run1.txt`（两次运行的日志、事后以普通用户读到的主机状态、脚本 `run011-rootful.sh`）；`run2-firewall.txt`（诊断日志与脚本 `run011-fw.sh`）
