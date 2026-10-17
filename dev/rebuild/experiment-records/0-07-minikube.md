# 0-07 minikube 跑 BrickKit 生成的 Kubernetes 清单（含外壳）

## 1. 结论

**通过（v1.7.2）**。部署本身一开始就全部正常：清单生成、迁移 Job、Deployment 与探针、每个成员一个选中外壳 Pod 的 Service、成员挪出外壳、`status`、`down`；`mode: local` 与 `mode: debug` 配 `k8s` 被拒；`kubectl` 的 context 与 `k8s.context` 不符时被拒。

第一次（v1.7.1）**调用外壳成员的地址在 Kubernetes 上不可达**（FRB-004，严重）：BrickKit 给调用方注入的是“外壳的服务名 + 成员端口”（如 `http://demo-shell-0-1-0:8081`），外壳的 Service 只开放外壳自己的端口（8080），请求超时，而所有 Pod 都 healthy、`up` 与 `status` 全绿。BrickKit 在 v1.7.2 改为地址写成员自己的服务名（K8s 上有成员的 Service，Docker 与 Podman 上外壳挂着成员的网络别名），复测通过（第 9 节）：两条调用链、外壳里成员之间、`$endpoint:` 引用都通，成员挪出外壳前后调用方的地址不变。

## 2. 测了什么、为什么

计划第 0 步：“minikube 跑 BrickKit 生成的 Kubernetes 清单（含外壳承载成员）”，对应 K 行。要确认：本地构建的镜像怎样进集群；清单的形状（迁移、探针、外壳与成员的 Service）；跨组件调用、基础资源、外壳成员的寻址；拆回；`local`、`debug` 与错 context 的拒绝；`down`。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| BrickKit | CLI v1.7.1 |
| 集群 | minikube v1.38.1，单节点，Kubernetes v1.35.1，驱动 docker，CNI 是 Calico（这个 profile 以前装过）；没有独立的 `kubectl`，用转给 `minikube kubectl --` 的小脚本 |
| 基础资源 | 集群内另一个命名空间 `r007-base` 的 PostgreSQL 16 与 NATS 2.10（各一个 Deployment 与 Service）；部署文件的 `vars:` 把 `PG_HOST`、`NATS_URL` 指到它们的集群内域名 |
| 项目 | 与 0-06 相同的桩项目（`r007-setup.sh`）；部署文件 `target: k8s`、`k8s.context: minikube`、`namespace: r007`、`createNamespace: true` |
| 镜像 | 本机 `brickkit build`，再逐个 `minikube image load`（`build` 在 `k8s` 目标下提示了这条路） |

## 4. 怎样跑

`run007.sh`：基础资源部署进集群；`add`、填配置；`build` 并 load 镜像；`lint`、`up --dry-run`；`up`，在 Pod 里调用两条链与基础资源；不改任何东西再 `up`；beta 挪出外壳再 `up`；`mode: local`、`mode: debug` 配 `k8s`；`k8s.context` 改成别的集群；`down`。链路超时后用 `run007b.sh` 重新部署，在 Pod 里分别直连注入的地址与成员自己的 Service。

## 5. 结果

| 步 | 结果 |
| --- | --- |
| `build` | 7 个镜像建在本机 Docker，并提示“集群拉不到，本地集群用 `minikube image load` / `kind load docker-image`”；load 之后集群里都有 |
| `up --dry-run` | 15 份清单，按目录分 `deployments/`、`services/`、`migrations/`、`secrets/` 与 `namespace.yaml` |
| 清单形状 | 每个顶层组件一个 Deployment（replicas 1；startup、liveness、readiness 三个探针都打 `/healthz`；requests 100m / 128Mi，不设上限）；每个组件（含成员）一个 ClusterIP Service，成员的 Service 选中外壳的 Pod；迁移是 Job（`backoffLimit: 0`、`restartPolicy: Never`），alpha 作为外壳成员用自己的镜像迁移；外壳的成员配置（`BRICKKIT_SERVED_MEMBERS_CONFIG`）放在 Secret 里 |
| `up` | 16 s 完成：两个迁移 Job 先完成（日志里 `PG_HOST=pg.r007-base.svc.cluster.local`），4 个 Deployment 就绪；`status` 列出 7 个组件 |
| 基础资源 | 两个 Pod 经集群内域名连通 PostgreSQL 与 NATS |
| **调用链** | gamma → beta、delta → alpha 与 pyr **全部超时**。注入的地址：`DEMO_ALPHA_ENDPOINT=http://demo-shell-0-1-0:8081`、`DEMO_PYR_ENDPOINT=http://demo-pyshell-0-1-0:8091`；外壳 Service `demo-shell-0-1-0` 只有 8080，`demo-pyshell-0-1-0` 只有 8090 |
| 直连对照（run 1b） | 从 delta 的 Pod：`demo-shell-0-1-0:8081` 超时、`demo-alpha-0-1-0:8081` 通；`demo-pyshell-0-1-0:8091` 超时、`demo-pyr-0-1-0:8091` 通 |
| 再 `up` 一次（不改） | 正常，结果相同 |
| beta 挪出外壳 | 多一个 `demo-beta-0-1-0` Deployment，beta 的 Service 改为选中它自己的 Pod；外壳的 `BRICKKIT_SERVED_MEMBERS` 只剩 alpha；gamma → beta 通了，但 beta → alpha 仍走 `demo-shell-0-1-0:8081`，链路照样超时 |
| `mode: local` / `debug` 配 `k8s` | `--dry-run` 就拒绝（`CONFIG_INVALID`），说明“集群里的 Pod 到不了开发者的机器” |
| context 不符 | `up` 拒绝，写出部署文件要的与当前的 context，提醒“部署错集群无法撤回” |
| `down` | 删掉整个命名空间 `r007`（部署文件写了 `createNamespace`）；提示不碰 BrickKit 没部署的服务 |

## 6. 观察与异常

- **FRB-004 的原因**（源码 `internal/inject/inject.go` 的 `addEndpoints` 与 `resolveEndpointRef`）：被外壳承载的依赖，主机名一律取外壳的服务名，端口取成员自己的端口，不分部署目标。Docker 与 Podman 下外壳容器挂着每个成员的网络别名，容器名解析到外壳容器的 IP，任何端口都到得了，所以 0-04 到 0-06 都没暴露；Kubernetes 的 Service 只转发它声明的端口。BrickKit 的技能写着“k8s 上每个成员有一个选中外壳 Pod 的 Service——寻址都不用改”，Service 也确实生成了，只是注入的地址没用它。
- **问题是静默的**：健康检查只查自己，所以 Pod 全部 healthy、`up` 与 `status` 全绿，只有真正调用时才超时（5 s 后）。
- `$endpoint:` 引用走同一条规则（`resolveEndpointRef`），本项目 `config/vars.yaml` 的 `AUTHZ_BUNDLE_URL`、`IAM_JWKS_URL` 在 Kubernetes 上同样会指错（推断，未单独测）。
- 本地集群的镜像要手动 load：BrickKit 只给提示，不替用户做（与“构建是显式的一步”一致）。实验脚本照做即可。
- 这个 minikube profile 的 CNI 是 Calico，NetworkPolicy 会生效；以后测 `k8s.networkPolicy` 时可以直接用。

## 7. 影响

- K 行与 K8s 上带外壳的格子不再受阻（v1.7.2）。本地集群的镜像由实验脚本在 `build` 后 `minikube image load`。
- 地址写成员自己的服务名之后，成员进出外壳不改调用方的地址：拆回与合并（套件 C 的 R5）不会因为地址变化重建调用方。
- 不需要改设计。项目 `config/vars.yaml` 里描述旧规则（“被外壳托管时指向外壳”）的注释已改。

## 8. 原始数据

`dev/rebuild/experiment-data/0-07/run1.txt`（v1.7.1；含 `run007.sh`、`run007b.sh`、`r007-base.yaml`、生成脚本 `r007-setup.sh`，以及最后一次生成的三份关键清单）；`run2.txt`（v1.7.2 复测，含 `run007-2.sh`）

## 9. v1.7.2 复测（2026-10-17）

BrickKit 的修复：被外壳承载的成员，`*_ENDPOINT` 与 `$endpoint:` 的主机名用成员自己的服务名，和它单独运行时一样；名字由外壳容器的网络别名（Docker、Podman）或成员的 Service（K8s）落到外壳；外壳是本机进程时，调用它的容器的 `extra_hosts` 映射成员的名字。新增一条测试，核对生成物里每个 `http://主机:端口` 都有同名、开着那个端口的 Service。

复测前给 delta 加了一个配置项 `ALPHA_HELLO_URL: $endpoint:demo/alpha/api/hello`。

| 步 | 结果 |
| --- | --- |
| K8s，beta 在外壳里 | 注入 `DEMO_ALPHA_ENDPOINT=http://demo-alpha-0-1-0:8081`、`DEMO_PYR_ENDPOINT=http://demo-pyr-0-1-0:8091`、`ALPHA_HELLO_URL=http://demo-alpha-0-1-0:8081/api/hello`；外壳 Secret 里 beta 的 `DEMO_ALPHA_ENDPOINT` 同样是 `demo-alpha-0-1-0:8081`。gamma → beta → alpha、delta → alpha 与 pyr、外壳里 beta → alpha、`$endpoint:` 的地址都通 |
| K8s，beta 挪出外壳 | gamma → beta（自己的 Pod）→ alpha（外壳）通；delta 的 `DEMO_ALPHA_ENDPOINT` 拆前拆后都是 `http://demo-alpha-0-1-0:8081` |
| Docker，全部在容器 | 地址同样写成员名，两条链与 `$endpoint:` 都通 |
| Docker，Go 外壳是本机进程，其余在容器 | 容器的 `extra_hosts` 是 `demo-alpha-0-1-0:host-gateway`、`demo-beta-0-1-0:host-gateway`（以前是外壳名）；delta、gamma 的调用链与 `$endpoint:` 都通 |

**结论**：通过，FRB-004 关闭。
