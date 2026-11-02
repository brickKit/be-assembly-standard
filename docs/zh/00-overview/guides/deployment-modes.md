# 部署模式

## 解决什么问题

同一套组件可以有很多种跑法：放在哪种运行形态上（容器引擎、Kubernetes、本机进程），每个组件单独一个进程还是几个成员合进一个外壳，基础资源怎样放。本篇回答：**有哪些模式，默认用哪个，各要付出什么，怎样部署，出事时会怎样**。

依据是代表部署实验（D41，2026-10-17 到 11-02）的实测：一台机器，12 个组件、3 个外壳，小公司规模的数据与负载。机制与外壳的风险见[部署与运行](../../04-foundations/01-deployment-and-runtime.md)，引擎与基础资源的候选见[底层选择](../../04-foundations/README.md)。

## 默认

| 选择 | 默认 | 什么时候改 | 依据 |
| --- | --- | --- | --- |
| 容器引擎 | 有根 Podman，容器内以非 root 用户运行 | 客户要求引擎本身不以 root 运行：无根 Podman；客户已经在用 Docker，或要用只支持 Docker 的周边工具：Docker（同等支持） | D80 |
| Podman 上怎样跑 | Quadlet 单元（`podman: { units: quadlet }`），systemd 看护与开机拉起 | 开发机上要与本机进程（`mode: local`、`debug`）或焦点运行混用：compose（不写 `podman.units`） | D81 |
| 拓扑 | 全部单跑，每个组件一个进程 | 内存或 CPU 在部署的机器上真不够：合并进三个外壳——基础与主数据（`be/go-infra`）、库存信用销售出账（`be/go-core`）、打印（`be/py-render`）；热的组件要单独扩容或升级时仍单跑，成为混合 | A112 |
| 连接池代理 | 不加 | 许多进程或副本连同一个实例、连接数成为限制：加事务模式的代理 | A113 |
| 消息运输 | NATS JetStream | 只有一台小机器、每秒事件几十条以内、想少运行一个服务：只用 PostgreSQL 队列 | A114 |
| 数据库 | 一个实例、一个库，每个组件一个 schema | 隔离或运维要求：每组件一个库，或把一部分组件放进第二个实例（代价见“数据库与运输的放法”） | 协议 14 |
| 副本 | 每个组件一个 | 要扩容或缩短重启时的中断：加副本（见“出事时”） | 协议 01、04 |

## 6 种运行形态 × 3 种拓扑

**三种拓扑**：S 全部单跑（每个组件一个进程）；H 全部进外壳（上面三个外壳）；X 混合（实验里只有 `be/go-infra` 一个外壳，交易的 5 个组件单跑）。

| 形态 | 是什么 | 优势 | 劣势 | 适合谁 |
| --- | --- | --- | --- | --- |
| **P Podman**（默认有根） | 每个进程一个容器，没有常驻守护进程；有根时引擎以 root 运行，无根时以部署用户运行 | 没有守护进程：平台常驻约 0.14 GiB（无根实测），同一批里比 Docker 少约 0.4 GiB。有根：网络由内核转发，整套 CPU 比无根少 9–10%。用 Quadlet 单元时开机由 systemd 按依赖顺序拉起，不用别的开机设置 | 有根：引擎以 root 运行（容器里要用非 root 用户），`brickkit` 也由 root 运行；与 Docker 同机要放行转发规则。无根：网络在用户态转发（每千次约 13 CPU 秒），开机回来还要 linger、AppArmor 的配置等主机设置 | 单机交付的默认（有根）；要求引擎不以 root 运行时用无根；内存紧的小机器；RHEL 系 |
| **D Docker** | 同上，由 Docker 守护进程管理 | 最普及，周边工具最多 | 守护进程常驻约 0.55–0.7 GiB | 已经在用 Docker 的客户；中型单机 |
| **K Kubernetes** | 每个进程一个 Deployment（外壳的成员各有自己的 Service） | 自动重启、按组件扩容 | 单节点时控制面与 kubelet 常驻约 2 GiB（不含页缓存约 0.75）；崩溃时请求会挂住几秒 | 已有 Kubernetes、要自愈与扩容的中型与集团型客户；小客户不划算 |
| **L 本机进程** | BrickKit 的 `mode: local` 从源码直接运行，不用容器 | 不用装容器环境，一次启动、一次关闭 | 只活在一次 `up` 会话里，不重启、不开机启动，不能长期运行；`go run` 的包装常驻约 0.4 GiB | 开发、演示、不想装容器环境的试用；**不用于交付** |
| **LD、LP 本机 + 容器** | 少数组件本机从源码跑，其余在 Docker 或 Podman | 只有改动的组件从源码跑；整套开销与全在容器里看不出差别 | 本机部分只活在 `up` 会话里；本机进程经宿主机端口连数据库，容器的代理多转发一份 | 开发与调试一两个组件 |

| 拓扑 | 优势 | 劣势 |
| --- | --- | --- |
| S 全部单跑 | 隔离最好，每个组件可单独升级、单独看资源 | 进程与数据库连接最多 |
| H 全部进外壳 | 每种形态上组件 CPU 少 14–28%、组件内存少 32–37%，平台开销随进程数减少；延迟看不出差别 | 成员共进退：一个成员崩溃整个外壳重启，升级一个成员要重建外壳；一个外壳只能合并同一语言、同一 SDK 版本的成员；数据库每条连接变大，整套内存不一定省 |
| X 混合 | 热组件单独扩容、单独升级，其余合并 | 省得比 H 少（组件 CPU 少 6–16%） |

## 实测的消耗

整套 = 组件 + 基础资源（PostgreSQL、NATS、对象存储、Casdoor）+ 平台（容器引擎或集群）；实验里基础资源一直跑在 Docker 里，所以 P、K、L 行的整套还含为它们服务的那份 Docker（P 行约 251 MiB），P 行与 D 行整套的差不全是引擎的差——同一批里平台自己的内存 Podman 135 MiB、Docker 548 MiB。内存不含页缓存，CPU 是每秒 7 次请求的混合负载下。每一行在自己那一批测量里比；行与行之间来自不同的批，绝对数只能粗看（不同批整体可能差约 8%）。

| 形态 | S 全部单跑 | H 全部进外壳 | X 混合 |
| --- | --- | --- | --- |
| P 无根 Podman | 1.37 GiB；0.75 核 | 1.36 GiB；0.66 核 | 1.29 GiB；0.67 核 |
| D Docker | 1.97 GiB；0.71 核 | 2.04 GiB；0.62 核 | 1.88 GiB；0.66 核 |
| K Kubernetes（单节点） | 2.38 GiB；0.77 核 | 2.46 GiB；0.72 核 | 2.36 GiB；0.74 核 |
| L 本机进程 | 1.43 GiB；0.71 核 | 1.43 GiB；0.68 核 | 1.32 GiB；0.71 核 |

- **P 行是无根 Podman 的实测**：有根（默认）在另一批里整套 CPU 少 9–10%（Podman 自己的开销降到约五分之一，一部分挪到组件与数据库上），延迟 p50 低约 1.4 ms。
- **起步的机器**：整套容器放进 4 GiB、6 GiB 的上限都照常跑完，让出去的只是页缓存；按 4 GiB 起步，6 GiB 能留出数据库的页缓存。见[部署与运行的实测的预算](../../04-foundations/01-deployment-and-runtime.md#实测的预算)。
- **负载加倍**（7 → 14 次/秒）：核数只多五成多，延迟不升；数据加倍只让数据库多 10–15%。
- **外壳省的是 CPU 与平台，不一定是内存**：外壳的一条数据库连接为几个成员各缓存一套表，每条约是单跑的 2.4 倍；连接条数少了，PostgreSQL 的内存反而多约 210 MiB（Docker 的那一批），抵掉组件上省下的。
- **没量的**：负载上限、更多组件同机、多台机器、高可用。

## 怎样部署

每种形态都照这几步，下面只写各自不同的地方。

1. 准备基础资源：PostgreSQL、NATS JetStream（或只用 PostgreSQL 队列）、对象存储、身份产品。
2. 在装配项目里加组件与外壳：`brickkit add <组件 ID>@<版本>`；`brickkit.yaml` 就是锁文件。
3. 写 `deploy.yaml`：`target` 与组件列表；进外壳的成员写在外壳的 `members` 下；要从外部访问的写 `expose`。全部单跑（默认）是每个组件各占一行、没有 `members`；合并进外壳时的样子：

   ```yaml
   target: podman            # 或 docker、k8s
   components:
     - id: be/go-infra
       members:
         - id: infra/iam-casdoor
         - id: infra/authz
         # …… 其余安全与主数据成员
     - id: be/go-core
       members:
         - id: erp/inventory
         # …… 信用、销售、出账
     - id: be/py-render
       members:
         - id: infra/print
   ```

   混合是外壳带它的成员，其余各占一行。
4. 填 `config/`：每个组件的配置键；密钥写 `${VAR}` 或 `file://.secrets/…`，不写明文。部署里每个组件的对象存储地址（`OBJECT_STORE_URL`）用同一个主机名；令牌的签发者写固定字符串，不写 `$endpoint:`（[协议 19](../../06-protocols/19-config-secrets-registries-release.md#配置)）。
5. `brickkit build` 构建镜像，`brickkit up` 起来，`brickkit status` 看状态。
6. 冒烟：每条依赖边调一次，等调用方稳定（熔断器都关上、几秒内没有新的失败调用）再判断；刚换完拓扑时几个成员同时起来，先就绪的调用方调还没就绪的依赖，熔断器可能打开几秒，确认转后台推进，数据不受影响。

| 形态 | 不同的地方 |
| --- | --- |
| P Podman | `target: podman` 加 `podman: { units: quadlet }`：`up` 把每个组件与每个迁移生成为 Quadlet 单元，先跑完全部迁移，全部成功才装上并按依赖启动组件的单元（有一个失败就停下：组件照旧跑原来那份，之后崩溃重启、机器重启回来的也是原来那份）；日志用 `journalctl [--user] -u 'brickkit-<项目>_*'` 看。有根（默认）：主机照下面“为有根 Podman 准备主机”做一遍，`brickkit` 由 root 运行（`sudo brickkit up`）；无根：照“为无根 Podman 准备主机”，由部署用户运行 |
| D Docker | `target: docker`；容器的重启策略是 `unless-stopped` |
| K Kubernetes | `target: k8s` 加 `k8s:` 块（`context`、`namespace`、`createNamespace`）；镜像推到集群拉得到的仓库。外部访问经边缘（[边缘](../../04-foundations/09-edge.md)），实验没有接 Ingress |
| L、LD、LP | 要本机跑的组件或外壳写 `mode: local`；宿主机要有工具链（Go、uv）与源码；`brickkit up` 在前台运行，关掉它本机进程一起停，一个本机进程崩溃时同一会话的其他本机进程也停，容器照常 |

### 为有根 Podman 准备主机

以 root 做一次，之后 `brickkit up` 起的 Quadlet 单元在崩溃与机器重启后都会自己回来：

1. 装 Podman，至少 5.3（Quadlet 单元要用到的功能从这一版起才齐）。
2. **与 Docker 装在同一台机器时**：Docker 把转发策略设为丢弃，有根 Podman 的容器之间静默不通。在 `DOCKER-USER` 链放行 Podman 的网桥（`iptables -I DOCKER-USER -i podman+ -j ACCEPT` 与 `-o podman+` 各一条），并且开机时补回：Docker 每次启动重建自己的链，手加的规则重启就没了——用 BrickKit 排障页给的一次性单元 `podman-docker-forward.service`（`After=docker.service`，只在规则缺时才加），生成的单元自动排在它之后。只装 Podman 的机器不需要这一步。
3. `brickkit` 由 root 运行：`sudo brickkit up`、`down`、`status`（单元装进 `/etc/containers/systemd/brickkit-<项目>/`）。**部署脚本与 AI 固定用 root**：普通用户在同一个项目目录里 `up` 会被拒（`DEPLOYED_ELSEWHERE`，BrickKit v1.12.1 起），反过来也一样；要换边先在原来那边 `down`。
4. 镜像在 root 的存储里（`/var/lib/containers`，从镜像仓库拉或 `podman load`）；容器里以非 root 用户运行（镜像的 `USER`，[组件实现约定](../../01-conventions/06-component-implementation.md#健康检查与镜像)）：有根时容器里的 root 就是宿主机的 root。
5. Podman 的存储放在 fstab 里带 `nofail` 的盘上时：systemd 不保证它在单元启动前挂上，给所有 `brickkit-` 开头的单元加一个前缀 drop-in `/etc/systemd/system/brickkit-.service.d/storage.conf`，内容为 `[Unit]`、`RequiresMountsFor=<那块盘>`。
6. 检查：以 root 跑 BrickKit 的环境检查 `scripts/podman/check-environment.sh --units quadlet`：它真起两个容器试互通与删除，缺第 1、2、5 步时警告。

项目目录与其中的 `.brickkit/` 要留在原处：单元从那里挂入证书等文件型的配置。

验证：实验在 Ubuntu 26.04（与 Docker 同机）上做了一次真重启，系统的 `podman-restart.service` 与 `podman.socket` 都没启用：网络在线 → Docker → 补回规则的单元 → 12 个组件全部 healthy，L3 场景全部通过（那次是 v1.12.0，开机还先跑一遍迁移；v1.12.1 起开机不跑迁移）；`down` 之后再重启什么都不回来。

**开发机用 compose 时**还要：装 Docker 的 Compose V2（`podman compose` 转给它，不需要 Docker Engine）；`systemctl enable --now podman.socket`（`brickkit` 经它连 Podman；要让一个组的用户经它操作时，给套接字设 `SocketGroup=`，并加 `ExecStartPost=/bin/chmod 0711 /run/podman`——Podman 包的 `tmpfiles.d` 每次开机把这个目录建成 0700；这个组的成员等同 root）；`systemctl enable podman-restart.service`（系统级的开机单元，等网络在线之后拉起重启策略为 `always` 的容器）；第 2 步的单元再加 `Before=podman-restart.service`。compose 这条路实验也真重启过一次：网络在线 2 秒后开机单元拉起 12 个组件，全部 healthy、没有重启、启动阶段过后没有警告，但开机不按依赖顺序、不跑迁移。

### 为无根 Podman 准备主机

以部署用户的身份做一次，之后 `brickkit up` 起的 Quadlet 单元在崩溃与机器重启后都会自己回来。第 2、3、4 步缺了哪一步，开机时都会静默失败：服务器开机后没人登录，没有人会发现。

1. 装 Podman，至少 5.3。
2. **AppArmor 限制无特权用户命名空间的发行版**（Ubuntu 23.10 起，`sysctl kernel.apparmor_restrict_unprivileged_userns` 为 1）：`podman` 要在 apparmor 包自带的 `/etc/apparmor.d/podman` 配置下运行（它什么都不限制，只允许 `userns`）。没有它，在用户的 systemd、ssh 或普通终端里启动的 `podman` 建不了自己的用户命名空间（`failed to reexec: Permission denied`）；snap 里的终端（例如 VS Code）不受影响，所以容易漏看。这份配置被删过时（BrickKit 旧版的 `scripts/podman/fix-apparmor.sh` 会删它，dpkg 不会补回被删的配置文件），用 `sudo apt-get install --reinstall -o Dpkg::Options::=--force-confmiss -o Dpkg::Options::=--force-confold apparmor` 恢复，再 `sudo apparmor_parser -r /etc/apparmor.d/podman`。检查：`systemd-run --user --wait --pipe podman unshare cat /proc/self/attr/current` 输出 `podman (unconfined)`。比关掉整个限制窄。
3. `sudo loginctl enable-linger <用户>`：用户的服务开机就启动，不等有人登录；Quadlet 单元就是用户的服务。
4. Podman 的存储（`~/.local/share/containers`）放在另一块盘、那块盘在 fstab 里带 `nofail` 时，给 `user@<uid>.service` 加 drop-in `RequiresMountsFor=<那块盘>`：systemd 不保证这样的盘在用户的 systemd 之前挂上。
5. 1024 以下的端口无根发布不了：前面的网关占 443，或调低 `net.ipv4.ip_unprivileged_port_start`。
6. 镜像要在 Podman 的存储里（从镜像仓库拉，或 `podman load`）。
7. 检查：从用户的 systemd 里跑环境检查（`systemd-run --user --wait --pipe bash <路径>/check-environment.sh --units quadlet`），缺第 1、3、4 步时警告。

单元自动等网络在线（依赖 Podman 自带的 `podman-user-wait-network-online.service`），不用另配。项目目录与其中的 `.brickkit/` 要留在原处。

验证：用 Quadlet 单元起一套，真重启一次机器，不登录、不跑 `up`，等网络在线后 `brickkit status` 全部 healthy。实验在 Ubuntu 26.04 上，`podman-restart.service` 停用、没有等网络的附加配置时，12 个组件按依赖顺序全部回来，L3 场景全部通过；`down` 之后再重启什么都不回来。v1.12.1 上又真重启一次，重启前故意做了一次迁移失败的 `up`：开机没有跑迁移、没有失败的单元，回来的是失败之前的那份。

**开发机用 compose 时**还要：装 Docker 的 Compose V2；`systemctl --user enable --now podman.socket`；`systemctl --user enable podman-restart.service`（开机时拉起重启策略为 `always` 的容器）；**让它等网络**：它写的 `After=network-online.target` 在用户的 systemd 里不起作用，加用户级 drop-in `~/.config/systemd/user/podman-restart.service.d/wait-network.conf`，内容为 `[Unit]`、`Wants=podman-user-wait-network-online.service`、`After=podman-user-wait-network-online.service`——没有它，地址由 DHCP 慢一点取到时，无根网络命名空间先于网络起来、之后一直不通，组件连不上宿主机上的基础资源、反复重启。实验用 compose 真重启了三次才查全：缺 AppArmor 的配置时一个都没回来，缺等网络时拉起了但连不上基础资源，都补上后全部回来。

## 出事时、升级时、版本不整齐时

实测在 Docker 与 Kubernetes 上，每秒 7 次请求的背景负载下注入故障，每次之后核对整套的不变量（没有丢或重复的确认与账单、没有停在中间的过程、库存与信用的占用对得上、发件表发完）：全部成立。

| 情形 | 会怎样 |
| --- | --- |
| 一个进程崩溃 | 容器约 5 秒后被拉起，负载只在崩溃那一秒失败几个请求；Kubernetes 上约 3 秒后重新就绪，那几秒打到它的请求会挂住、失败约 10 个。进外壳时整个外壳重启，Kubernetes 上同一个 Pod 10 分钟内反复崩溃会被退避拉长 |
| 被依赖的组件重启 | 调用方的熔断器打开 5 秒起（试探失败加倍到 30 秒，D79），这段时间同步确认转后台推进，之后全部走完 |
| 消息系统停 2 分钟 | 事件积压在发件表（约 4000 条），恢复后约 2 秒清空，投影 1–2 秒追平 |
| 授权组件停 | 单跑时写操作在授权视图有效期内照常（约 31 秒）后被拒；授权在外壳里时，和它同外壳的成员一起停 |
| 数据库重启 | 各组件自己重连 |
| 机器重启 | Podman 的 Quadlet 单元由 systemd 拉起：组件在它依赖的组件健康之后才启动，开机不跑迁移（迁移只由 `up` 跑，库结构在那时已经迁好；有根与 Docker 同机时排在补回放行规则的单元之后，无根要“为无根 Podman 准备主机”的第 2–4 步）。Docker 与开发机上的 compose 靠引擎拉起（Docker 服务开机启用与 `unless-stopped`；Podman 的 `podman-restart.service`）：不按依赖顺序，也不跑迁移。两种都要组件自己重试连接还没起来的依赖。`down` 之后什么都不回来；本机进程从不回来。实验在有根与无根 Podman、两种方式上都真重启验证过 |
| 升级一个组件 | 被依赖的组件升级要连锁发布依赖方（它们写的是精确版本）；`up` 只换改动的容器，Docker 约 11 秒、Kubernetes 约 18 秒；进外壳的成员升级是重建外壳、只换外壳一个容器 |
| 滚动升级时新旧版本并存 | SDK 版本不同的组件之间调用、事件、截止时间、追踪都互通；只做加法的契约下新旧两版共用库与流；调用旧版没有的操作答 501 `CAPABILITY_UNSUPPORTED`；旧版的迁移遇到新版迁移过的库按成功结束。收缩迁移（删列、改名）之后还在跑的旧版写入会出错：破坏性变化所有组件一起更新 |
| 一个组件跑几个副本 | 只发布一次、只执行一次、只生效一次都成立；停或崩一个副本时在途的确认过程续上，负载只丢正在被杀的进程上的请求；组件之间的调用靠服务端定期关连接按时间分到各副本，短时突发会偏到一个副本（[调用与错误](../../04-foundations/08-calls-and-errors.md)） |
| 拆出、合回外壳 | 各一次 `brickkit remove`／`add` 外壳加 `up`；合进一个新外壳前要先给它准备数据库登录角色与配置 |

## 数据库与运输的放法

| 放法 | 实测 |
| --- | --- |
| 每组件一个 schema、一个库（默认） | 参照 |
| 每组件一个库 | 业务结果相同；延迟、组件的 CPU 与内存、连接数看不出差别；数据库的 CPU 低约 3.5%（原因没查）。每个库要各自备份与恢复 |
| 交易组件单独一个 PostgreSQL 实例 | 业务结果相同；延迟、CPU、连接总数看不出差别；多约 160 MiB 内存。两个实例各自备份、各自恢复，整套恢复时要对齐恢复时刻 |
| 审计库与业务库分开 | 业务库回退到某个时刻、审计库不动时，已转运的审计都在，损失只有“产生而未转运”的那一段，逐组件算得出来 |
| 加事务模式的连接池代理（PgBouncer） | 后端连接约减半、数据库内存少约 200 MiB；整套 CPU 多约 9%、p50 多约 1.8 ms；组件一点不省。代理要开协议层的预编译语句（`max_prepared_statements`），否则设 `PG_POOLER_PREPARED=false`（[数据库引擎与连接](../../04-foundations/05-database-engine.md)） |
| 只用 PostgreSQL 队列（不起 NATS） | 每秒 7 次请求时整套 CPU 看不出差别，业务延迟与事件链走完的时间一样；NATS 空闲只占约 20 MiB。PostgreSQL 队列的吞吐上限更低，且一个开着不提交的事务会挡住同一实例里全部读取者（[消息运输](../../04-foundations/06-message-transport.md)） |

## 验收

选定组合之后，在客户的机器上：起整套，跑一遍真实的受保护请求、事件与后台任务；停一个进程看它回来；做一次升级；核对整套内存在机器的预算之内并留出页缓存。换拓扑、换引擎之后重跑这一遍，不能只看启动成功（[部署与运行的外壳的风险](../../04-foundations/01-deployment-and-runtime.md#外壳的风险)）。

## 依据

- 机器：Intel i5-12450H（12 线程）、14 GiB、NVMe，Linux 7.0；Podman 5.7.0（无根）、Docker 29.9.2、minikube v1.38.1（Kubernetes v1.35.1，单节点）、BrickKit v1.10–v1.11（测量），v1.12.0–v1.12.1（Quadlet 单元的重启）；performance 电源模式。
- 组件：身份、授权、审计、组织、币种、往来单位、产品、库存、信用、销售、出账（Go）与打印（Python）；外壳 `be/go-infra`、`be/go-core`、`be/py-render`。
- 负载：2 个法人、2 000 个产品、500 个客户、2 万张历史订单；开环每秒 7 次、20 个用户（列表 40%、报价转订单 25%、确认 20%、交货 10%、出账打印 5%）。
- 基础资源：PostgreSQL 16.15、NATS JetStream 2.10.29、RustFS 1.0.0-beta.12、Casdoor 4.1.0。

## 已知风险与待定

- 结论来自一台机器、12 个组件、小公司规模的负载；负载上限、更多组件同机、多台机器、多节点 Kubernetes、高可用都没有量，在路线的第 4 步另测。
- 有根与无根 Podman 都只在有 Docker 也在的机器上测过；只有 Podman 与 Compose 的机器没有端到端验证。有根的资源只量过整套 CPU（比无根少 9–10%，另一批），平台内存没有单独量。
- 机器重启后自己回来只在一台 Ubuntu 26.04 桌面机（Wi-Fi、自动登录）上验证过（Quadlet 单元有根一次、无根两次；compose 有根一次、无根三次）；其他发行版与 Docker 的开机拉起没有真重启验证。
- 现有组件与外壳的镜像都没有写 `USER`，容器里以 root 运行；有根 Podman 下这等同宿主机的 root。重建组件时按组件实现约定改成非 root 用户。
- 外部请求的边缘（Traefik）没有接上，实验用测试的入口代替；Ingress 未测。
- 本机进程只用于开发与演示：BrickKit 不重启、不开机启动它们，长期运行不在 BrickKit 的范围内。
- 每组件一个库、多实例的备份与恢复代价没有量。
- 外壳的数据库连接池上限、连接的最长寿命、每成员一个小池，哪种更省没有量。
