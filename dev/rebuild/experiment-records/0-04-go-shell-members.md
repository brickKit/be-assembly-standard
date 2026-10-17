# 0-04 Go 外壳承载成员；成员版本不一致时被拒

## 1. 结论

**通过**。外壳用自己的 `go.mod` 引入成员模块，`main` 按 `BRICKKIT_SERVED_MEMBERS_CONFIG` 初始化成员，就能在一个进程里承载两个成员。成员之间仍走真实调用，地址指向外壳加成员端口。成员挪出外壳后改用自己的镜像独立运行，配置一字不改。

版本不一致分四种，BrickKit 能拦下三种，最后一种只能靠外壳自己拦：

| 不一致在哪 | 谁发现 | 什么时候 |
| --- | --- | --- |
| 部署文件让外壳承载它没编进的组件 | BrickKit：`CONFIG_INVALID` | `up --dry-run` 就拒绝 |
| 项目的成员版本与外壳声明的不同（升级成员、外壳没跟） | BrickKit：`upgrade` 自动保留外壳编进的旧版本（`requiredBy`），新版本单独运行 | `upgrade` 时 |
| 外壳的 `component.yaml` 改了成员版本，本机镜像没重建 | BrickKit：比对镜像标签 `io.brickkit.shell.members` | `up` 时（`--dry-run` 不查镜像） |
| 声明都对，编进外壳的**代码**是另一个版本（依赖锁或 `vendor` 漂移） | **只有外壳自己**：启动器比对“要承载的版本”与“编进来的版本”，不符就退出 | 外壳启动时；容器反复重启，`up --wait` 报 unhealthy |

所以协议 17 要求启动器在“编译进来的版本不同”时拒绝启动，这条检查是必要的：BrickKit 的镜像标签取自 `component.yaml`，不看编进去的代码。

## 2. 测了什么、为什么

计划第 0 步：“外壳的 Go 构建怎样取成员模块”。这里验证模块怎样组合，以及成员版本不一致时谁会拒绝：外壳自己的 `go.mod` 引入成员，BrickKit 只核对版本，不替外壳编译。模块取法先用本地 `replace`；从 GitHub 按标签取的那一半，在第 4 步建外壳时验证。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| BrickKit | CLI v1.5.0 |
| Docker | 29.7.1；构建镜像 `golang:1.26-alpine`，运行镜像 `alpine:3` |
| Go | go1.26.0 |
| 成员 | `demo/alpha`（端口 8081，`GET /api/hello`）；`demo/beta`（8082，依赖 alpha，`GET /api/chain` 调用 alpha）。每个都是一个 Go 模块：包导出 `Version` 常量和 `Handler(cfg map[string]string) http.Handler`，另有 `cmd/server` 供单跑。都放在项目的 `components/`（本地安装源） |
| 外壳 | `demo/shell`（8080），在项目的 `shell/`；`go.mod` 用 `require` 引入两个成员，再用 `replace` 指向本地目录；构建前 `go mod vendor`，镜像里 `go build -mod=vendor` |

## 4. 怎样跑

1. 用 `r004-setup.sh` 生成项目、两个成员与外壳，`go vet` 通过。
2. `brickkit add --local`，然后 `lint --all`、`up --dry-run`；查看生成的 compose 与外壳的 env 文件。
3. `brickkit build`；查看三个镜像的标签。`up`，在外壳容器里访问两个成员的服务名与端口。
4. 用例：
   - C1：把 beta 挪出外壳；
   - C2：部署文件把外壳没编进的 gamma 放进外壳；
   - C3：alpha 的本地仓库改成 0.2.0，看 `up`；再 `upgrade` 到 0.2.0；
   - C3b：同样的漂移下 `build` alpha 0.1.0；
   - C4：外壳声明改成 alpha 0.2.0、项目升级，不重建镜像就 `up`；C4b：重建外壳后再 `up`；
   - C5：所有声明都写 alpha 0.1.0，但 `vendor` 进外壳的代码是 0.2.0；
   - C6：外壳声明承载 beta，二进制里却没有 beta 模块。

每个用例结束后恢复三层文件（第一遍 C3 留下了 `config/demo-alpha@0.1.0.yaml`，污染了 C4–C6，作废重跑，见原始数据第 3、4 部分）。

## 5. 结果

| 步 | 结果 |
| --- | --- |
| `add --local` | 一条命令加进三个组件，`deploy.yaml` 把 alpha、beta 直接嵌在外壳下；`brickkit.yaml` 的外壳行带 `kind: shell` |
| `lint --all`、`up --dry-run` | 0 个错误；只有一个服务 `demo-shell-0-1-0`，网络别名 `demo-alpha-0-1-0`、`demo-beta-0-1-0`；成员配置在 env 文件（0600）的 JSON 里，beta 的 `DEMO_ALPHA_ENDPOINT=http://demo-shell-0-1-0:8081` |
| `build` | 三个镜像都建了（成员各有自己的镜像）；只有外壳镜像带标签 `io.brickkit.shell.members=demo/alpha@0.1.0,demo/beta@0.1.0` |
| `up` 与调用 | 外壳 healthy；日志 `serving demo/alpha@0.1.0 on :8081`、`serving demo/beta@0.1.0 on :8082`；经服务名访问 alpha 与 beta 都通，beta → alpha 走 `http://demo-shell-0-1-0:8081`；`status` 列出两个成员“in shell”；外壳 2.7 MiB |
| C1 挪出 beta | beta 用自己的镜像独立运行，`/api/chain` 照样拿到外壳里 alpha 的结果；外壳只承载 alpha；启动顺序外壳 → beta；内存外壳 1.8 MiB、beta 2.3 MiB |
| C2 承载没编进的组件 | `up --dry-run` 拒绝：`CONFIG_INVALID`，“demo/gamma is listed in the members of demo/shell@0.1.0, but that shell's component.yaml does not contain it”，列出编进的成员 |
| C3 本地仓库 0.2.0、项目仍是 0.1.0 | `up --dry-run` 通过，项目继续跑 0.1.0（容器形态下合理；`lint` 给出提示：源码是 0.2.0，项目固定在 0.1.0） |
| C3 再 `upgrade demo/alpha@0.2.0` | 0.2.0 成为默认版本、单独运行；0.1.0 留下并标 `requiredBy: [demo/beta, demo/shell]`，在外壳里写成 `demo/alpha@0.1.0`。就是文档里的第三条出路（两个版本都留），由 `upgrade` 自动完成 |
| C3b 同样漂移下 `build demo/alpha@0.1.0` | 拒绝：“component not found … Install sources tried: local-dev, local-shells”。不会用 0.2.0 的源码打出 0.1.0 的镜像；但报错没说本地源里是 0.2.0（见第 6 节） |
| C4 声明改了、镜像没重建 | `up --dry-run` 通过；`up` 拒绝：“the local image of shell demo/shell@0.1.0 contains other member versions than its component.yaml declares”，写出镜像里与声明里的成员，建议 `build --force` |
| C4b 重建外壳后 | 标签变成 `demo/alpha@0.2.0,demo/beta@0.1.0`；`up` 通过，日志 `serving demo/alpha@0.2.0` |
| C5 声明都对、编进的代码是 0.2.0 | BrickKit 全部通过（标签照 `component.yaml` 写 `demo/alpha@0.1.0`）；外壳启动即退出：“asked to host demo/alpha@0.1.0, but the code compiled in is 0.2.0”，容器反复重启，`up` 报 unhealthy，`status` 显示 restarting |
| C6 声明承载 beta、二进制里没有 | BrickKit 通过；外壳启动即退出：“this shell has no module demo/beta”，同样反复重启 |
| 恢复后重建、`up` | 通过；最后 `down` |

## 6. 观察与异常

- **镜像标签只是声明的副本**。`build` 写的 `io.brickkit.shell.members` 来自外壳的 `component.yaml`，不是从二进制里读出来的。所以它能发现“声明改了、镜像没重建”（C4），发现不了“声明没改、编进的代码变了”（C5）。
- **Go 的构建信息能当启动器的依据**。`go version -m` 显示外壳二进制记下的是 `go.mod` 里的版本：`dep example.test/alpha v0.1.0`，用了 `replace` 的另起一行 `=> ../../../components/demo/alpha (devel)`。启动器用 `runtime/debug.ReadBuildInfo()` 就能拿到每个成员模块编进来的版本，不需要手写 `Version` 常量。但 `replace` 指向本地目录时，构建信息里仍是 `go.mod` 写的版本号，而代码可能已经变了（C5 正是这种情况）。所以发布的外壳镜像里不应该有 `replace`。
- **启动器拒绝时，外壳在 Docker 上反复重启**，`up --wait` 只说 unhealthy，原因要看外壳日志（`docker compose -p <项目> logs <服务名>`，`status` 也这样提示）。所以启动器的报错要一行说清、点名成员与两边的版本。
- **`up --dry-run` 不查镜像标签**，C4 只在真正 `up` 时拦下。
- **C3b 的报错不够直接**：本地源里组件是 0.2.0，`build demo/alpha@0.1.0` 报“没有在任何安装源里找到”，建议里讲的是 git 与市场组件，没提本地源里有别的版本。同一情况下 `lint` 的提示是清楚的。已写给 BrickKit（FRR-004，低优先级）；v1.6.0 已改，见第 9 节。
- 写成员时“一个模块一个配置表、`main` 从环境填、外壳从 JSON 填”的形状，单跑与外壳两种形态都不用改代码（文档 `04-shell/02-json-injection` 的建议），这里验证可行。

## 7. 影响

- **第 2 步 `be-sdk-go` 的外壳启动器**：
  - 用 `debug.ReadBuildInfo()` 读出每个成员模块编进来的版本，与 `BRICKKIT_SERVED_MEMBERS_CONFIG` 的 `version` 比对，不符就点名成员、拒绝启动（协议 17 已要求，这里给出实现依据）；
  - 成员注册时带上自己的 Go 模块路径（或由启动器从注册类型的包路径推出），用来在构建信息里找到对应的依赖；
  - 构建信息里有 `replace` 的成员，在发布镜像里拒绝启动，只在开发构建里放行并警告。
  - 记进第 2 步的验收：上面的 C5、C6 两种情况，外壳都必须拒绝启动。
- **第 4 步建外壳**：`go.mod` 按标签从 GitHub 取成员（`/v3` 路径），不用 `replace`、不需要 `vendor`；验证这一半，并重做 C4、C5。
- **组件的形状**：成员包导出由配置表构造的处理器；`cmd/` 下的 `main` 只负责单跑，与组件实现约定的“一个模块入口”一致。
- 不需要改设计。

## 8. 原始数据

`dev/rebuild/experiment-data/0-04/run1.txt`（含生成脚本 `r004-setup.sh`）；之后的复测见第 9 节

## 9. v1.6.0、v1.6.1 复测（2026-10-17）

### 9.1 结论

**通过**，FRR-004 与 FRB-001 关闭。

| 项 | BrickKit 的改动 | 复测结果 |
| --- | --- | --- |
| C3b 的报错（FRR-004，v1.6.0） | `build` 仍拒绝用 0.2.0 的源码打 0.1.0 的镜像，但写出本地仓库里的版本，给出两条出路：在仓库里检出项目固定的版本再构建；或 `upgrade` 到仓库的版本。`git -C` 的路径按当前目录写 | 符合 |
| 只写 `deployment.image` 的组件（通知，v1.6.0） | 来自本地源也一律拉取，不再按根目录的 `Dockerfile` 构建；`lint`、`build` 警告没用上的 `Dockerfile` | 符合；但 `up` 不警告，工作区改过的代码静默不生效（FRB-001） |
| `up` 的警告（FRB-001，v1.6.1） | `up`（含 `--dry-run`）对要用镜像启动的组件做同一项检查，给出同一条警告，照常启动 | 符合 |

**对重建的影响**：新组件带代码、要在本机构建的，`component.yaml` 必须写 `deployment.build`（项目技能 `brickkit-component` 已写明）。旧的 `components/frontend/standard`（1.0.1）只写了 `image`；它不在 `brickkit.yaml` 里，属于将从零重建的 2.x 代码（D59），不改。

### 9.2 怎样测

同一个 `r004-setup.sh` 重建桩项目。

- C3b：alpha 的工作区改成 0.2.0（`component.yaml` 与 `Version`），项目仍固定 0.1.0，分别在项目根目录与 `config/` 里 `build demo/alpha@0.1.0`；再把 alpha 做成 git 仓库（标签 `0.1.0`、`0.2.0`，工作区在 0.2.0）重做一遍。
- 只写 `image`：beta 只写 `image`、目录里留着 `Dockerfile`；引擎里先放一份用发布时的代码构建的同标签镜像（代替 registry 里那份）；然后改工作区里 beta 的代码（版本不变），用 C1 的布局（alpha 在外壳里，beta 单独运行）直接 `up`，看 `/api/chain` 回答的是哪份代码。

### 9.3 结果

| 步 | CLI | 结果 |
| --- | --- | --- |
| C3b，项目根目录 | v1.6.0 | 照旧拒绝（`COMPONENT_NOT_FOUND`）；多出 `Local repository: components/demo/alpha holds 0.2.0, not this version` 与两条建议，`upgrade` 那条说明别的组件还依赖的旧版本会留下、要有自己的镜像 |
| C3b，`config/` 里 | v1.6.0 | 路径改成 `../components/demo/alpha`，照着敲能用 |
| C3b，alpha 是 git 仓库 | v1.6.0 | 报错与建议同上；照建议 1 检出 `0.1.0`、`build`、切回，构建成功，工作区回到 0.2.0 |
| 只写 `image`：`lint --all` | v1.6.0 | 警告 “declares only deployment.image … the Dockerfile next to it is never used”，建议写 `build: {dockerfile: Dockerfile}` |
| 只写 `image`：点名 `build demo/beta@0.1.0` | v1.6.0 | 报 “declares no deployment.build, so there is nothing to build”，不再交给 Docker |
| 只写 `image`：beta 挪出外壳后 `up --dry-run` | v1.6.0 | compose 里 beta 只有 `image:`，没有构建段，即拉取 |
| 只写 `image`：直接 `up` | v1.6.0 | **没有任何警告**，`up` 与 `status` 全绿；容器跑发布的镜像，`/api/chain` 回答的是旧代码。源码里这条警告只在 `lint` 与 `build` 调用 |
| 只写 `image`：`up --dry-run`、`up` | v1.6.1 | 两次都在启动前给出同一条警告，照常启动（回答的仍是旧代码，这是声明的行为） |
| beta 改写 `build: {dockerfile: Dockerfile}` | v1.6.1 | 警告消失；`up` 报 `IMAGE_MISSING`，要求先 `build demo/beta@0.1.0`；构建后 `up`，回答的是工作区的新代码 |

两处小地方，不再反馈：alpha 不是 git 仓库时建议 1 照样写 `git -C … checkout`（这时用不上，另两条够用）；`lint` 的这条警告借用了 `MANIFEST_INVALID` 这个错误码。回复说的“外壳承载、要跑迁移的成员也查”没有测：桩成员没有迁移。

### 9.4 原始数据

`dev/rebuild/experiment-data/0-04/` 下：`run2.txt`（v1.6.0，C3b 与只写 `image` 的通知）、`run3.txt`（v1.6.0，`up` 静默运行旧镜像）、`run4.txt`（v1.6.1，FRB-001 复测）；各自附生成它的脚本。
