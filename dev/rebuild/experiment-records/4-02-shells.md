# 4-02 三个外壳：按标签编进成员、在部署好的格里通过剖面、重做 0-04 的 C4 与 C5

## 1. 结论

**通过。** `be/go-core`、`be/go-infra`（Go）与 `be/py-render`（Python）按标签取成员（Go 的 `go.mod`、Python 的 `uv.lock`，不用 `replace`、不从本地路径装），由 BrickKit 从标签构建、部署进 D·H2 格：五个探针成员（核心剖面）与三个外壳（外壳剖面，含 CK-OBS-05）全部“符合”。C4（声明改了、镜像没重建）由 BrickKit 拒绝；C5（声明对、编进的代码不对）BrickKit 放行、外壳启动器拒绝并点名每个成员。

途中在部署好的格里找到并修了三处 SDK 缺口与一处协议缺口（第 6 节），记了一条给 BrickKit 的问题（FRB-006）。

## 2. 测了什么、为什么

计划第 4 步“外壳三个（`go.mod` 按标签取成员、不用 `replace`，重做 0-04 的 C4、C5）”；[step4-plan.md](../step4-plan.md) 的 T4.2、T4.3。0-04 当时用本地 `replace` 验证了一半，这里验证另一半：发布的外壳只从标签取成员，以及两种不一致在真实外壳上的拦法。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| 机器 | Linux 7.0.0-38-generic，12 核，14 GiB |
| 引擎 | Docker 29.7.1 |
| BrickKit | CLI v1.8.1 |
| 外壳 | `be/go-core@3.0.2`、`be/go-infra@3.0.2`（Go，`be-sdk-go` `v3.0.0-alpha.4`）、`be/py-render@3.0.2`（Python 3.14.4，`be-sdk-python` `v3.0.0a3`） |
| 成员 | `test/probe-go`、`-go2` 在 `go-core`；`test/probe-go3` 在 `go-infra`；`test/probe-py`、`-py2` 在 `py-render`；都是 3.2.1 |
| 基础资源 | `be-postgres`、`be-nats`、`be-rustfs`（`make up`），容器经 `host.docker.internal` 访问 |

## 4. 怎样跑

1. 格的描述 `dev/rebuild/experiment-cells/D-H2/cell.yaml`（外壳与精确版本、各外壳承载的探针、调用链 go → go2 → go3 → py → py2 → go）。
2. `cd tools/be-acceptance/conformance && uv run python -m cells create <格目录>`：从头建 BrickKit 项目（`init`、两个安装源、`add` 外壳、按格写 `deploy.yaml`、移除这格不承载的成员；每个探针与外壳在宿主机 30000 + 端口上暴露）。
3. `uv run python -m cells prepare <格目录>`：建库与角色（探针的 schema、属主与运行角色；外壳登录角色持有成员的运行角色 `WITH INHERIT FALSE`）、签发部署的证书、建桶、清空探针的流、写每个组件的配置（下一个探针用 `$endpoint:<ID>` 与 `$endpoint:<ID>:grpc`）。
4. `cd <格目录> && brickkit build && brickkit up`。
5. `uv run python -m cells profile <格目录>`：从外部观测并按剖面判定，最后 `docker stop` 全部容器看体面停止；报告写到 `<格目录>/reports/`。
6. C4：`docker tag be-go-core:3.0.1 be-go-core:3.0.2`（镜像里是成员 3.2.0，声明是 3.2.1），`brickkit up`。
7. C5：从标签 `3.0.2` 克隆 `be-go-core`，只把 `go.mod` 的探针改回 `v3.2.0`，按真实镜像的标签 `docker build`（标签仍写 3.2.1），`brickkit up`；之后恢复真实镜像、`brickkit down`。

## 5. 结果

| 项 | 结果 |
| --- | --- |
| 构建 | `brickkit build` 从标签构建 8 个镜像（3 个外壳、5 个成员镜像供迁移）；外壳二进制的构建信息：`dep github.com/brickKit/be-acceptance/probes/go/v3 v3.2.1`，没有 `=>` |
| 启动 | `brickkit up` 约 20 秒：5 个迁移（成员镜像）后 3 个外壳 healthy |
| 冒烟 | 五个探针两两之间在 gRPC（mTLS）与 HTTP 两面调用都通；每个探针收到上一个的 2 个事件（其中 1 个约 100 KB 经对象存储）并把 1 个转成调用 |
| 剖面（成员） | 5 个探针都“符合”：入口参数与重复迁移（成员镜像）、配置错误 78、健康与就绪与 gRPC 端口（容器内）、自描述、各自的就绪日志、体面停止（摘除期间 503 `NOT_READY`）、库内的表与角色、发布的信封（含大事件的引用，在部署内取回核对）、日志行、访问日志、输出中没有凭据、指标 |
| 剖面（外壳） | 3 个外壳都“符合”：健康、就绪、带成员的自描述、体面停止退出 0、输出的每一行（含成员的行）、`/metrics` 每个序列带成员的 `component` 标签 |
| C4 | `up` 拒绝：“the local image of shell be/go-core@3.0.2 contains other member versions than its component.yaml declares”，列出镜像里与声明里的成员，建议 `build --force`（`experiment-data/4-02/c4.txt`） |
| C5 | BrickKit 放行（标签对）；外壳启动即退出，每个成员两条：“module … at v3.2.1, but the build info has v3.2.0”与“3.2.1, the version compiled in is 3.2.0”；`up` 报外壳 unhealthy（`c5.txt`） |

## 6. 观察与异常

- **两个外壳编进同一组成员时没法原地升级外壳**（FRB-006）：`upgrade be/go-core` 把成员都写进被升级的外壳，与 `go-infra` 承载的成员冲突，BrickKit 发现后恢复了三份文件。格因此改为每次从 `cell.yaml` 重建（`cells/create.py`）。BrickKit v1.8.2 已修复（按部署文件里的嵌套判断承载，别的外壳承载的成员留在原处），同一复现复测通过（`experiment-data/4-02/frb006-retest-v1.8.2.txt`）；格仍从 `cell.yaml` 重建，每格从干净的项目开始。
- **探针怎样找到下一个探针**：探针不声明依赖（链按格组合，可以成环），BrickKit 不注入 `*_ENDPOINT`，而两种 SDK 只给声明的依赖建客户端。按协议已有的“授权、身份的地址是配置里的引用”推广为 P4.26：配置给出的组件地址（`$endpoint:`）由运行时给出与依赖相同的客户端（Go `HTTPAt`、`GRPCAt`，Python `http_at`、`grpc_at`）；`be-protocol` `v3.0.0-alpha.3`，`be-sdk-go` `v3.0.0-alpha.3`，`be-sdk-python` `v3.0.0a2`；探针 3.2.0 改用 `PROBE_NEXT_URL`、`PROBE_NEXT_GRPC_URL`。
- **部署好的格里剖面抓到的 SDK 缺口（已修，`be-sdk-go` `v3.0.0-alpha.4`、`be-sdk-python` `v3.0.0a3`）**：①外壳里的成员不写自己的就绪日志，只有外壳写（P1.12；协议 17 要求单跑与在外壳里行为一致）；单跑的进程测试发现不了。②Python 外壳的输出里有 gRPC C 核心的纯文本行（`ssl_transport_security.cc … No match found for server name`），破坏“每行一个 JSON”（P10.1）：起因是 Go 客户端握手时不发服务端的名字（SNI），Python 服务端（gRPC 核心）每个连接都记一条。Go 客户端改为把目标的派生 DNS 名作为 SNI，Python SDK 默认关掉 gRPC 核心自己的日志（`GRPC_VERBOSITY=NONE`，运维显式设置时保留）。
- **重跑迁移**：BrickKit 生成的 `compose.yaml` 里环境文件是相对路径，`docker compose run` 要带 `--project-directory`。
- **大事件的引用地址**：预签名地址里的主机是 `host.docker.internal`，宿主机上解析不到；剖面在部署内（成员容器里）取回，与真实订阅者的位置一致。
- **一个与时间有关的测试缺陷**：Go SDK 的 `TestTwoReplicasRunACronSlotOnce` 在柏林时间 10 月 18 日 02:00 之后每次都失败：副本启动后按数据库时钟也会执行当天的时刻，测试却数“总共一次”。按测试缺陷改为“每个时刻只执行一次”（`be-sdk-go` `v3.0.0-alpha.3`）。

## 7. 影响

- 协议：P4.26（配置给出的组件地址）进 `v3.0.0-alpha.3`。
- 部署工具（第 4、5 步）：签发服务证书要带派生的 DNS 名（P8.5）；对象存储的桶、外壳登录角色与成员角色的授予由准备脚本做（这里是 `cells/prepare.py`）。
- 给 BrickKit：FRB-006。
- 报告：外壳的“编进 ≠ 承载”在实测中成立，两种不一致各有一道拦截。

## 8. 原始数据

`dev/rebuild/experiment-data/4-02/`：八份剖面报告（`*.json`）、`c4.txt`、`c5.txt`、`frb006-upgrade-shell.txt`、`frb006-retest-v1.8.2.txt`。
