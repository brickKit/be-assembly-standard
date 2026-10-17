# 0-05 全部组件与外壳 `mode: local`（`target: docker`，基础资源在 Docker）

## 1. 结论

**通过，有两处要在实验里绕开**。Go 与 Python 的单跑组件和外壳都能以本机进程运行，BrickKit 推断或按 `local.runCommand` 启动它们，地址全部改写成 `localhost`，包括外壳成员配置 JSON 里的值；跨进程、跨语言、经外壳的调用都通，基础资源经改写后的地址可达。BrickKit 文档写的看护行为全部核对属实：Ctrl+C 与关终端体面停止；一个进程崩溃，其余本机进程一起停、`up` 结束、容器照常；`down` 与 `status` 管不到本机进程，只提示会话的进程号。

| 要绕开的 | 影响 | 本项目的做法 |
| --- | --- | --- |
| `mode: local` 不跑迁移；提示里的命令是镜像里的路径（`/server migrate`），宿主机上不存在 | L、LD、LP 行每个有表的组件都要先手动迁移 | v1.7.0 起单跑的本机进程、v1.7.1 起本机外壳承载的成员，都写 `local.migrationCommand`，`up` 先从源码迁移再启动（FRR-005、FRB-003，第 9 节） |
| Go 默认用 `go run`，编译出的程序是它的子进程，`go run` 本身常驻 | 每个 Go 进程多约 25–28 MiB 常驻内存（程序本身约 9 MiB）；冷启动含编译 | L 行的内存把组件进程与工具链包装分开报；冷启动分冷、热编译缓存两种报（见第 7 节） |

## 2. 测了什么、为什么

计划第 0 步：“全部组件与外壳以 `mode: local` 运行”。L 行（全部本机进程）与 LD、LP 行（部分本机进程）依赖这一机制。要确认：Go 与 Python 的单跑组件与外壳都能这样跑；地址怎样改写（含外壳成员的配置 JSON、基础资源地址）；文档写的看护行为（停止、崩溃、`down`、`status`）是否属实；迁移、端口冲突、仓库版本不符时怎样。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| BrickKit | CLI v1.6.1 |
| 工具链 | 宿主机 go1.26.0、Python 3.14.4；Docker 29.7.1 |
| 基础资源 | `make up` 起的 `be-postgres`（5432）、`be-nats`（4222），在 Docker；组件只做 TCP 连接检查，不写数据 |
| Go | 外壳 `demo/shell`（8080）承载 `demo/alpha`（8081）与 `demo/beta`（8082，调用 alpha）；单跑 `demo/gamma`（8083，调用 beta，声明了 `migration`）。外壳与 0-04 相同：自己的 `go.mod` 用 `replace` 引入成员 |
| Python | 外壳 `demo/pyshell`（8090）承载 `demo/pyr`（8091）；单跑 `demo/delta`（8092，调用 alpha 与 pyr）。都只用标准库，写 `local.runCommand`；外壳经 `sys.path` 引入成员模块（代替安装包） |
| 配置 | 每个组件必填 `PG_HOST`、`PG_PORT`、`NATS_URL`，都写 `$var:`，`config/vars.yaml` 与本项目相同（`host.docker.internal`） |

## 4. 怎样跑

`r005-setup.sh` 生成项目，`brickkit add --local`，填配置，部署文件里四个顶层条目都写 `mode: local`。`run005.sh` 依次做：

1. 冷编译缓存（实验专用的 `GOCACHE`）下 `up`，等 7 个端口就绪；调用两条链，查各进程的基础资源连接、环境变量、内存；`status`、`down`；然后 Ctrl+C（SIGINT）。
2. 热缓存下 `up`，然后关终端（SIGHUP）。
3. `kill -9` gamma。
4. delta 改为容器，其余仍是本机进程；容器调用本机外壳；再 `kill -9` gamma。
5. beta 在外壳的成员条目上写 `mode: local`，离开外壳单独运行。
6. 8082、8083 先被别的程序占着，再 `up`。
7. gamma 的工作区改成 0.2.0，项目仍固定 0.1.0。
8. 照 `up` 的提示手动跑 gamma 的迁移。

`up` 用 `setsid` 放进单独的会话，代替一个终端。第 4 部分容器里的探测用了 `localhost`，busybox 的 `wget` 先解析到 `::1`，桩服务只监听 IPv4，探测失败（不是 BrickKit 的问题）；用 `127.0.0.1` 重做（`run005b.sh`）。

## 5. 结果

| 步 | 结果 |
| --- | --- |
| `lint`、`up --dry-run` | 通过；生成的 compose 没有服务；列出 4 条启动命令：两个 Go 的 `go run .`，两个 Python 的 `runCommand`；为每个本机进程生成 `local-debug.<服务名>.env` |
| 地址改写 | 单跑组件：`DEMO_*_ENDPOINT=http://localhost:<成员端口>`，`PG_HOST=localhost`，`NATS_URL=nats://localhost:4222`，`PORT` 等于 `deployment.port`。外壳：`BRICKKIT_SERVED_MEMBERS_CONFIG` 里每个成员的配置同样改写；成员端口照声明 |
| 冷启动 | 11.7 s 到 7 个端口全部就绪（含两次 Go 编译）；热缓存 0.69 s；beta 单独出来、多一次编译时 1.1 s |
| 监听 | Go 外壳一个进程监听 8080、8081、8082；Python 外壳一个进程监听 8090、8091；gamma、delta 各一个 |
| 调用 | gamma → beta（Go 外壳）→ alpha（同一外壳）通；delta（Python）→ alpha（Go 外壳）与 pyr（Python 外壳）通 |
| 基础资源 | 5 个组件经 `localhost:5432`、`localhost:4222` 全部连通 |
| 内存（常驻） | Go 外壳程序 9.5 MiB、gamma 9.0 MiB；各自的 `go run` 父进程 25–28 MiB；Python 外壳 22.4 MiB、delta 24.5 MiB |
| `status` | “No components need to be started as containers”，提示本机会话的进程号；不列本机进程 |
| `down` | 不碰本机进程，只提示会话的进程号；之后 7 个端口仍在监听 |
| Ctrl+C | `up` 退出码 0，全部进程停止，端口释放 |
| 关终端（SIGHUP） | 同上 |
| `kill -9` gamma | 其余本机进程停止，`up` 退出码 1（`ENGINE_FAILED`），列出崩溃的进程与最后几行输出。退出码显示 1：`up` 看到的是 `go run` 的退出码，被杀的是它的子进程（输出里有 `signal: killed`） |
| delta 改为容器 | 容器先启动并 healthy，然后才启动它依赖的本机外壳；容器里依赖地址仍是服务名（`http://demo-shell-0-1-0:8081`），由 `extra_hosts` 解析到宿主机，调用通；基础资源经 `host.docker.internal` 连通 |
| 容器在时 `kill -9` gamma | 本机进程全部停止、`up` 结束；容器照常运行，但它的调用返回 502，直到 `down` |
| beta 离开外壳 | 外壳只承载 alpha；beta 以 `go run ./cmd/server` 单独运行（BrickKit 在 `cmd/` 下找到唯一的 main 包）；gamma → beta → alpha 照样通 |
| 端口被别的程序占着 | `--dry-run` 不报；`up` 时 gamma 绑定失败退出，`up` 结束并列出“address already in use”。在那之前 BrickKit 先打印了“demo-gamma-0-1-0 listening on port 8083”：它探测到的是占着端口的那个程序（见第 6 节） |
| 仓库版本不符 | `up --dry-run` 就拒绝（`CONFIG_INVALID`），给出 `upgrade` 与 `git checkout` 两条出路 |
| 迁移 | `up` 与 `--dry-run` 都提示迁移不会自动跑，建议“在这台机器上手动运行 `/server migrate`”；宿主机上没有 `/server`（127）。从源码运行 `go run . migrate` 可以 |

## 6. 观察与异常

- **迁移是 L 行最大的缺口**。`migration.command` 按定义在组件镜像里运行，`mode: local` 没有镜像，BrickKit 没有“从源码迁移”的写法，提示却把镜像里的命令原样给出。本项目所有带表的组件都会遇到。已写给 BrickKit（FRR-005：`local` 下从源码运行迁移的写法，`up` 像容器那样先迁移；提示不再给出镜像路径）。
- **“listening”可能是别的程序**。端口被占时，BrickKit 的就绪探测连上了占着端口的程序，先报组件在监听。这次组件随即因绑定失败退出，所以只是一行误导；组件绑定失败后不退出时，就会被当成就绪。文档写明“别的程序占着的端口要到引擎绑定时才失败”，这一点符合；误报是额外的。已写给 BrickKit（FRB-002，轻微）。
- **容器先于它依赖的本机进程启动**。混合时 `up` 先交给引擎启动容器，再启动本机进程；compose 的 `depends_on` 不能指向本机进程。按本项目的规则这不坏事：健康检查只报告进程存活，依赖不在时组件重试。文档没写这一点，记在这里，不反馈。
- **`go run` 常驻**。BrickKit 推断出的 Go 启动命令是 `go run`，它编译后以子进程运行程序，自己留着，常驻内存是程序的约 3 倍；退出码也经它转手（被信号杀死报 1）。要避免可以写 `local.runCommand`，用 `sh -c 'go build -o … && exec …'` 之类的写法，但那不是使用者默认得到的形态。
- **工具链来自宿主机**。本机进程用宿主机的 Go 与 Python（这里 Python 3.14.4），镜像里是镜像的版本（`python:3.13-alpine`）；L 行与容器行的差别里混着语言版本的差别。
- 退出码、地址改写、崩溃摘要、Ctrl+C 与关终端的行为都与 `brickkit docs 01-three-layers/03-deploy-yaml` 的 `mode` 一节、`02-project-guide/06-up-and-down` 一致。

## 7. 影响

- **计划（已修订“负载与测量”）**：
  - L、LD、LP 行在 `up` 之前由脚本逐个跑组件的迁移（从源码）；FRR-005 有发布版支持后改用 BrickKit 的写法。
  - L 行内存按“组件进程”与“工具链包装（`go run`）”分开报；冷启动分冷、热编译缓存报。
  - 宿主机的 Go 与 Python 版本与镜像对齐（镜像标签按宿主机版本选），报告写明两边的版本。
- **第 2、3 步的 SDK**：模块入口提供迁移子命令，单跑、外壳、从源码运行都能调用（Go：`go run . migrate`；Python 同理）；Python 外壳的成员导入方式在第 3 步按包安装定下（这里用 `sys.path` 代替）。
- **LD、LP 行**：容器先于本机进程启动，组件必须能在依赖不在时启动并重试（已是现行规则）；“冷启动到全部就绪”算到最后一个本机进程就绪。
- 不需要改设计。

## 8. 原始数据

`dev/rebuild/experiment-data/0-05/run1.txt`（含 `run005.sh`、`run005b.sh` 与生成脚本 `r005-setup.sh`）

## 9. v1.7.0、v1.7.1 复测（2026-10-17）

### 9.1 结论

**通过**，FRB-002、FRR-005、FRB-003 关闭。迁移的规则统一成“代码在哪里跑，迁移就在哪里跑”。

| 项 | BrickKit 的改动 | 复测结果 |
| --- | --- | --- |
| 端口被别的程序占着（FRB-002，v1.7.0） | 启动任何本机进程之前检查它们要绑的全部端口（含外壳替成员监听的端口），被占报 `PORT_CONFLICT`、一个都不启动；`--dry-run` 不查 | 符合 |
| 本机进程从源码迁移（FRR-005，v1.7.0） | 新增 `local.migrationCommand`；`mode: local` 时 `up` 用与进程相同的环境变量先迁移再启动，失败报 `MIGRATION_FAILED`；没写时提示不再给出镜像里的命令 | 符合；但本机外壳承载的成员仍用成员镜像迁移（FRB-003） |
| 本机外壳的成员从源码迁移（FRB-003，v1.7.1） | 外壳以本机进程运行、成员有本地仓库时，成员按自己的 `local.migrationCommand` 在成员目录里迁移，不再需要也不再使用成员镜像；没写就只提醒，不退回镜像。另加：从源码的迁移与同组件更高版本的容器迁移会跑反时报 `CONFIG_INVALID`；带代码、有迁移、没写 `local.migrationCommand` 时 `lint` 警告 | 符合（顺序保护没测） |

**对计划的影响**：本机进程的几行全部改用 `local.migrationCommand`，不再由脚本在 `up` 之前迁移（计划“负载与测量”已改）。第 2、3 步的组件模板与外壳成员都写上这个字段。

### 9.2 结果

| 步 | CLI | 结果 |
| --- | --- | --- |
| 8083（gamma）、8082（beta，由 Go 外壳监听）被别的程序占着，`up` | v1.7.0 | `PORT_CONFLICT`，两个端口一次列全（点名 `demo-gamma-0-1-0`、`demo-beta-0-1-0`），一个本机进程都没启动；不再出现“listening” |
| gamma 写 `localPort: 8183`，8083 仍被占 | v1.7.0 | 正常启动，gamma 在 8183，链路通 |
| gamma 写 `local.migrationCommand`（先打印环境再 `go run . migrate`） | v1.7.0 | `--dry-run` 列在“启动前会执行的数据库迁移”；`up` 先输出 `demo-gamma-0-1-0-migration` 前缀的迁移输出与“migration finished”，再启动进程；迁移的环境与进程相同（`PG_HOST=localhost`、`PORT=8083`、`COMPONENT_ID=demo/gamma`） |
| gamma 的迁移以 3 退出 | v1.7.0 | `MIGRATION_FAILED`，gamma 不启动，会话结束，没有端口在监听 |
| gamma 去掉这个字段 | v1.7.0 | 提示改为“`migration.command` 在镜像里运行，不能照原样在这台机器上运行”，指向 `local.migrationCommand` |
| 本机 Go 外壳承载的 alpha 写 `migration` 与 `local.migrationCommand` | v1.7.0 | 没用到 `local.migrationCommand`：`--dry-run` 列出 `/server migrate`，`up` 用 alpha 的镜像起迁移容器。这台机器上的 `demo-alpha:0.1.0` 是 0-04 那个项目 4 小时前构建的、代码不同，照样被拿来跑（桩程序不认 `migrate`，迁移容器一直不退出，手动停掉）；镜像挪开后报 `IMAGE_MISSING`。当时源码里 `local.migrationCommand` 只对本机进程自己读取（`internal/cli/up_local.go`、`internal/compose/local.go`）（FRB-003） |
| 同上，alpha 的镜像挪开 | v1.7.1 | `--dry-run` 列出 alpha 的源码命令；`up` 不报 `IMAGE_MISSING`、不起任何容器；先 `demo-alpha-0-1-0-migration` 的输出与“migration finished”，再启动外壳。迁移在 `components/demo/alpha` 里运行，环境是 alpha 自己的配置（`COMPONENT_ID=demo/alpha`、`PG_HOST=localhost` 等），不带 `BRICKKIT_SERVED_MEMBERS_CONFIG`；`up` 为 alpha、beta、pyr 各写了一份 `local-debug.<成员服务名>.env` |
| alpha 的迁移以 3 退出 | v1.7.1 | `MIGRATION_FAILED`，外壳不启动，会话结束，没有端口在监听 |
| alpha 去掉 `local.migrationCommand` | v1.7.1 | 不迁移、不起镜像；提醒点名 `Shell: demo/shell@0.1.0`，说明“迁移从源码跑，从不用镜像”；`lint --all` 对 alpha 与 gamma 各警告缺这个字段 |

### 9.3 观察

- **本机进程之间不按依赖等待**。v1.7.1 下 gamma、delta、Python 外壳先启动并监听，之后 alpha 的迁移才跑、Go 外壳才启动；gamma 依赖外壳里的 beta。成员的迁移只挡住它的外壳，不挡依赖外壳的本机进程。这与第 6 节“组件在依赖不在时重试”的规则一致，不反馈。
- 三处小地方，不再反馈：成员缺字段的提醒，第二条建议仍写“before starting the process”（对成员来说是在外壳启动之前）；`lint` 的这条警告借用 `MANIFEST_INVALID` 错误码；迁移顺序保护（从源码的迁移与同组件更高版本的容器迁移）没有测，要构造两个版本并存，留到 0-08。

### 9.4 原始数据

`dev/rebuild/experiment-data/0-05/` 下：`run2.txt`（v1.7.0；第 3 部分卡住、手动停掉，run 2b 把镜像挪开重做）、`run3.txt`（v1.7.1）；各自附生成它的脚本。
