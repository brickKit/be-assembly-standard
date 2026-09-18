# 阶段五 A · 迁移到真实 servedBy（准备工作）

✅ **本文档记录的工作已全部完成（2026-09-14 ~ 2026-09-16）。**

> **阶段五分两部分**：本文档（05a）是正式开始组合排列测试之前的准备工作——把 `be-assembly-standard` 自己从阶段四遗留的"挪用 `local:true`"迁移到 brickKit 正式发布的真实 `servedBy` 机制，因为后面 05b 的全部组合测试都要建立在这次迁移的真实结果之上。真正的组合排列测试在 `docs/plans/05b-组合矩阵验证.md`。
>
> **写法说明**：这份文档不拆成"计划"和"执行记录"两份配对文档（早前一度这样做过，事后发现来回跳转、互相引用反而更难读）。每个子任务一节，"要验证什么 → 真机做的过程 → 撞到的问题 → 最终结论/决策"全部写在同一节里，只看这一份文档就能完整看懂整个迁移过程。

## 背景：为什么要做这次迁移

阶段四做外壳时，`servedBy` 还没有正式发布，只能用 `local: true` 反过来表达"这个组件不生成独立容器"，外壳自己的容器编排、网络别名、启动顺序全靠 `infra/shell-compose.yml` 手写 + `Makefile` 里一套 `shell-up`/`teardown-up` 互斥切换脚本模拟。2026-09-14，brickKit 正式发布 `servedBy`（本机装的版本从 v0.3.0 一路追到本次迁移收尾时的 v0.4.3），不再是提案或开发中的功能——这次迁移把手写的模拟机制全部换成真实机制，验证过程本身也是后面 05b 全部组合测试能够成立的地基。

## 0.1：`infra/shell-compose.yml`/`shell-up`/`teardown-up` 能不能退休

**要验证的核心判断**：`servedBy` 落地后，"外壳态"和"全拆态"可能不再需要是两个互斥的部署状态，只是同一份 `brickkit.yaml` 里"谁写了 `servedBy` 谁没写"的区别，一条 `brickkit up` 就能生成正确的混合拓扑。

**最小子集真机实验**（2026-09-14）：新建一个临时 local source，把零依赖的 `mdm/customer`/`mdm/product` 从 `local: true` 改成 `servedBy: infra/go-core-shell-poc@1.0.0`（一个指向已构建镜像的临时外壳条目），其余 12 个组件不动。

**⚠️ 真实撞到的问题**：第一次 `brickkit up --dry-run` 直接报错——`mdm/customer`/`mdm/product` 的 `component.yaml` 都在 `deployment.labels` 里声明了各自的 `prometheus.io/port`（值本来就该不同：8080 vs 8082），`servedBy` 的 labels 合并规则是"同名同值跳过、同名不同值报错"，跟环境变量合并用的是同一套规则，但**环境变量合并对 `COMPONENT_ID`/`COMPONENT_VERSION` 这类"语义上必然因组件而异"的变量做了无条件排除，labels 合并没有做同样的收窄**——只要两个组件各自声明了 `prometheus.io/port`、又被收编进同一个外壳，必定 100% 撞车。临时绕过（删掉这一行、验证完 `git checkout` 还原）让实验能继续往下走。

**绕过之后 `--dry-run` 成功，生成结果符合预期**：外壳容器拿到 `BRICKKIT_SERVED_MEMBERS=mdm-customer-1-0-7,mdm-product-1-0-8`，两个成员没有生成独立 service；一个真实存在弱依赖的独立组件 `infra-bff-mobile` 拿到的地址正确指向外壳容器的网络别名（`MDM_CUSTOMER_ENDPOINT=http://mdm-customer-1-0-7:8080`）；仍是 `local: true` 的其它组件走的还是旧的 `host.docker.internal`——确认 `local:true` 和 `servedBy` 在同一份 `brickkit.yaml` 里确实互不干扰。

**结论与决策**：
1. 核心判断成立——`infra/shell-compose.yml`/`shell-up`/`teardown-up` 大概率可以退休，留到 0.4 全量切换、跟旧拓扑逐项对比后再做最终决定。
2. **发现的 labels 冲突问题写成一次性反馈文档给 brickKit**（`prometheus.io/port` 这类标签需要跟 env 变量一样被排除在合并范围外），0.4 节全量迁移前必须先有个方向（自己删标签，或等 brickKit 收窄规则）。
3. **迁移全部完成后的最终决策**（回填于 0.5/0.6 完成之后）：`infra/shell-compose.yml`、`infra/shell-k8s/`（本仓库从未有过）已删除；`Makefile` 的 `shell-gen`/`shell-image`/`shell-up`/`shell-down` 四个目标已删除（纯 `brickkit up` 完全覆盖）；`teardown-up`/`teardown-down` **保留**，但内部机制从"临时去掉 `local:true`/`localPort`"改成"临时去掉 12 个成员的 `servedBy`、禁用 4 个外壳组件条目"——这两个目标存在的理由变了：不再是"切换部署形态"，而是"临时切到设计书 §13.7 拆回门禁专用的测试状态"。《BrickEnterprise 设计书.md》第 13 章已全面回填（§13.1 机制三改写成真实 `servedBy`；§13.6 对接分工表重写；§13.7 拆回门禁检验动作改成"去掉 `servedBy`"；§13.8 重写为"外壳启动器自己要做的事"；§13.9 重写为"合并态与全拆态不再互斥"，改用 `teardown-up`/`teardown-down` 的临时测试窗口框架），顺带发现并如实标注：读 brickKit 源码（`internal/k8s/servedby.go`）确认合并部署现在**原生支持 K8s**，反转了"合并只能 Docker 交付"这条旧铁律（本项目自己尚未真机验证，见 05b Task 6）。

## 0.2：`be-ops` 产出 4/7/8 是否还需要——结论比原计划预期的更深一层

**原计划以为的缺口**：只缺"端口/schema"。**读代码读出来的真实缺口更大**：缺整个模块自己的 `configSchema` 解析结果（`pgSchema`/`otelBaseUrl`/`authzBundleUrl`/`iamJwksUrl` 等）。

逐条结论：
1. **产出 4（`shellconfig`）本来就没绑定 `local:true`，不用动**——它只读每个组件自己的 `component.yaml`/`assembly.yaml`，从一开始就跟 `brickkit.yaml` 写的是 `local:true` 还是 `servedBy` 无关。
2. **产出 7（`shellenv`）的"地址改写"那部分被 `servedBy` 原生取代**——0.1 真机验证过 `*_ENDPOINT` 已经由 brickKit 直接合并进外壳容器自己的 `environment`，`shells/go` 里对应的 `exportDependencyEndpoints` 可以整个删除。
3. **但产出 7 还有第二个职责，原计划没意识到**：它的输入（brickKit 生成的 `local-debug.<service>.env`）里其实还带着组件完整的 `configSchema` 解析结果，这是模块读自己配置项的唯一来源（十七条第 16 条：模块代码零 `os.Getenv`，只走 `rt.Config`）。而这份文件**只在组件是 `local: true` 时才生成**——`servedBy` 成员既不生成容器也不是 `local:true`，brickKit 目前没有为它生成任何等价产物，这部分职责不是"被原生取代"，是"数据源直接消失了"。
4. 读 brickKit 源码确认这份数据 brickKit 自己其实算过（`Resolve(cfg, graph, states, env)` 的 `env` 参数就含全部组件已经注入完的完整结果），只是没存下来，直接在内存里被丢弃——`servedBy` 场景下这部分只能靠我们自己"另算一份"。
5. **产出 8（`shelldepends`）确认整个退休**——外壳间启动顺序现在由 `servedBy` 原生的 `depends_on` 改写覆盖，0.1 已真机验证。

**最终方案**（修正版）：把 `configSchema` 解析挪进 `be-ops` 自己做，但只做"配置合并"这一层最简单的部分（`brickkit.yaml` 的 `config:` 字面量覆盖 `component.yaml` 的 `configSchema.properties.<key>.default`），不碰地址改写；产出 7/8 两个包整体删除。

## 0.3：`shells/go`/`shells/python` 接上 `BRICKKIT_SERVED_MEMBERS`（跟 0.2 一起做，2026-09-14）

`buildModules` 改成：读 `os.LookupEnv("BRICKKIT_SERVED_MEMBERS")`（用 `LookupEnv` 不用 `Getenv`，必须能区分"变量不存在"与"空字符串"——本次调研最容易被写错的一个细节），按逗号切分成版本化服务名集合，只实例化真的在这个集合里的模块；变量不存在时直接报错，不静默退化成"全部实例化"的旧行为。

**改动落地**：`be-ops`（`v0.1.9`）新增 `LoadBrickkitConfig`/`MergeConfig`，`shellenv`/`shelldepends` 两个包及其子命令整体删除；`shells/go`（`v0.4.6`）删除 `exportDependencyEndpoints`，`buildModules` 改成"按 `SHELL_NAME` 挑外壳 → 按 `BRICKKIT_SERVED_MEMBERS` 筛成员"双重过滤，新增/重写 7 条单元测试覆盖全部边界情况；`shells/python`（`v0.2.4`）对称修改，真机复核比 Go 侧更完整（用真实 `TEST_PG_DSN` 跑通含真实装 `infra-print` 的集成测试）。三个仓库 `go build`/`go vet`/`go test`/`pytest` 全绿，均已 commit + tag + push。

**遗留知识债**：`be-ops` 原来那份"brickKit 生成的 dotenv 文件多行值原样嵌入未转义换行符"的真机坑（PEM 解析两轮才修对）随 `shellenv` 一起删除，已回填进 `docs/dev/field-tested-pitfalls-log.md` C27，避免知识随代码消失。

## 0.4：`brickkit.yaml` 全量真机切换（2026-09-14~15，撞到 3 个平台缺口 + 1 个自有设计缺陷）

**步骤 1-2：labels 冲突的正式修复**。11 个 Go 组件 + `infra/print` 各自的 `component.yaml` 永久删掉 `prometheus.io/port`（保留 `scrape`/`path`），4 个外壳自己的 `component.yaml` 上补一份（合并后指标只能走外壳这一个共享端口）。12 个组件逐个 `make bump-version` + 测试全绿 + `make image` + commit/tag/push，级联带出 `infra-bff-mobile`。

**步骤 3：给 4 个外壳补真实 `component.yaml`**——发现的新问题比计划预期更具体：`sources` 的 `type: local` 目录结构要求，最终在两个外壳仓库里各建 `deploy/shell/<name>/component.yaml`，`brickkit.yaml` 新增两条 `sources`；组件 ID 用新 scope `shell/`，`registry/ports.tsv` 的组件数量门禁新增 `_shell-` 前缀豁免（`be-ops@v0.1.10`/`v0.1.11`）；`metadata.version` 直接复用外壳仓库自己的 git tag；新增 `shellName`/`shellHealthPort` 两个 configSchema 项解决"三个 Go 外壳实例共用一份镜像，运行时怎么分身"的问题。

**步骤 4-5：`brickkit.yaml` 主体改造**。12 个成员的 `local: true`/`localPort` 换成 `servedBy: shell/<外壳>@<版本>`，`expose`/`exposePort` 整段删除（servedBy 成员不生效）。**真机验证发现的关键点**：`resources.bindings` 必须直接挂在外壳的 componentId 上——`servedBy` 只合并 `Source == SourceEndpoint` 的变量，`DATABASE_*`/`MQ_*` 是 `Source == SourceResource`，从不在合并范围内，真正持有连接池的是外壳自己。

**`--dry-run` 一次性通过**，但警告揭出第二个平台缺口：`CheckRunningResourceBindings` 完全不知道 `servedBy`，只认"组件自己的 componentId 在不在某条资源的 bindings 里"，真实 `up`（非 `--dry-run`）会直接硬阻断。临时应对：每条资源的 `bindings` 里同时保留外壳和每个成员的 componentId。已反馈 brickKit。

**真机执行 `brickkit up`（去掉 `--dry-run`）撞到第三个、也是最严重的平台缺口**：`collectTargets` 判断"该不该跳过"只查了 `c.Local`，完全没查 `c.ServedBy`，导致命令直接报 `no such service` 整体失败，一个容器都起不来。已反馈 brickKit。临时绕过：跳过 `brickkit up`，直接对生成好的 compose 文件跑 `docker compose up`。

**容器起来后 4 个外壳全部 crash-loop——这是自己这边的设计缺陷，不是 brickKit 的问题**：`SHELL_CONFIG_JSON` 原设计是"文件路径 + 挂载卷"，但 brickKit 的 manifest 模型根本没有 `volumes` 字段。停在这里，清理容器，未继续，全部改动 commit + push（含三份 brickKit 反馈文档）。

**brickKit 三个反馈全部真机修复（2026-09-15，CLI 升到 v0.4.1）**：
1. `collectTargets` 改成 `c.Local || c.ServedBy != ""`。
2. 资源绑定校验新增 `servingShellID`，外壳绑了资源等价于它收编的每个成员都绑了（比我们临时绕过的写法更彻底）。
3. labels 合并：`shell.Group` 去掉 `Labels` 字段，成员 labels 完全不参与合并，归到跟 `expose`/`hostname`/`replicas` 等同一类"声明了就警告+忽略"（选的是我们提出的方向，比猜测的两个方向都更彻底）。

升级后 `brickkit up --dry-run` 零警告零错误；真机 `brickkit up` 不再报 `no such service`，两个独立容器启动成功；4 个外壳容器仍因 `SHELL_CONFIG_JSON 未设置` crash-loop——收敛到只剩自己这边这一个缺口。三份反馈文档已删除（brickKit 已读取修复，"创建-读取-删除"的既定约定）。

## Task 0.4 收尾：5 个自有 bug（2026-09-15）

真机把 `brickkit.yaml` 全量切到 servedBy 之后，非 `--dry-run` 的真实 `brickkit up` 陆续暴露 5 个自己这边的缺口：

1. **`SHELL_CONFIG_JSON` 设计缺陷**：语义从"文件路径"改成"内容本身"——servedBy 的 manifest 模型没有 `volumes` 字段，没法挂载文件（`be-ops@v0.1.13`、`be-shell-go@v0.4.7`、`be-shell-python@v0.2.5`）。
2. **`MergeConfig` 的 SCREAMING_SNAKE_CASE 转换缺失**：`erp/sales` 的 `defaultWarehouseId` 真机 panic（`be-ops@v0.1.13`）。
3. **密钥类配置项的 JSON 损坏/git 泄露风险**：`appTokenSigningKeyPem` 等 6 项真实密钥改成 shell 自己独立的 configSchema 项 + 进程环境兜底（`be-ops@v0.1.15`、`be-shell-go@v0.4.8`、`be-shell-python@v0.2.6`）。
4. **`host.docker.internal` 网络拓扑失效**：`infra-authz`/`infra-iam-casdoor` 在 servedBy 下不再有自己的容器/发布端口，13 处手写字面量（`authzBundleUrl`/`iamJwksUrl`）改成外壳网络别名——`docs/design/infra-iam-casdoor.md` 的依赖表明确禁止任何组件对这两者声明依赖边（会打断 `slot:iam`/`slot:authz` 可替换性），所以这个手写字面量+人工同步纪律本身**继续保留**，这次只是把值改对。
5. **`shell/py-render` 自己 `/healthz` 路径与 HEAD 方法注册缺失**：brickKit 生成的健康检查用 `wget --spider`（HEAD）探测 `/healthz`，外壳自己手写的健康检查路径是根路径 `/` 且没注册 HEAD——`be-sdk-python` 早就记录过同一个坑，外壳没复用，改成同 `besdk` 一致的写法（`be-shell-python@v0.2.7`）。

真机复验：`docker compose down` 清场 → `brickkit up --dry-run` 零警告 → 真实 `brickkit up` → 6 个容器全部 `healthy` → 从三个外壳容器内分别 `wget` 探健康端点都成功。

## Task 0.5：档 0/档 1/档 2 + 附录 E 全链路（2026-09-15）

**发现 1：`make tier0`/`make tier1` 在 servedBy 下全部退化成 SKIP**——两者都依赖某个组件"真的有自己的独立容器"，servedBy 收编后这个前提不成立。根因追到 `make teardown-up`（设计书 §13.7 拆回门禁专用）已经失效——它调用的 `strip-shell-local.py` 只认 `local: true`/`localPort`，全量切到 servedBy 后一行都不剩，"名义上拆回、实际上什么也没变"。

**修复**：新建 `infra/scripts/strip-shell-servedby.py`（取代 `strip-shell-local.py`）：临时去掉 12 个成员的 `servedBy`、禁用 4 个外壳组件条目。过程中发现并修复两个连带缺口——`resources.bindings` 的 `servingShellID` 等价判定只在成员仍被 servedBy 收编时成立，脱离后必须给每个成员补回独立绑定；12 个成员本来就该有的 `expose: true`（阶段一起的既有约定）迁移时被一并删掉，teardown 时也要临时加回来。同时删除已彻底被 servedBy 取代的 `infra/shell-compose.yml`、`Makefile` 的 `shell-gen`/`shell-image`/`shell-up`/`shell-down` 四个目标。

真机验证：`make teardown-up` → 14 个独立容器 → `make tier0`（6 项 PASS，`grpcurl` 未装 SKIP）→ `make tier1`（25 项全部 PASS）→ `make teardown-down` 恢复。

**发现 2：`make seed-data` 在 servedBy 下同样失效**——8 个组件（`mdm-customer`/`mdm-product`/`erp-inventory`/`erp-finance`/`erp-sales`/`infra-authz`/`infra-print`/`crm-opportunity`）各自的 `scripts/seed.sh` 都假设自己能拿到独立容器名或宿主机发布端口。用户明确要求"不要考虑工作量，只考虑完整度/正确性"。

**修复方案**：目标地址一律改用 brickKit 自己给依赖方注入 `*_ENDPOINT` 时用的同一条转换规则直接拼（componentId+version 转小写、`/`和`.`替换成`-`）——这条地址不区分组件是否独立容器，两种形态都能正确解析。REST 调用改成起一次性"工具箱"容器（`curlimages/curl`）加入 brickkit 网络。真机踩到一个连带坑：工具箱容器默认非 root 用户，host 侧 `mktemp` 建出的 cookie jar 权限属主是宿主机用户，容器内 curl 读写不了（症状是"Please login first"，完全看不出是权限问题），修复：`docker run` 加 `--user "$(id -u):$(id -g)"`。

8 个组件逐一真机验证通过，`make seed-data` 完整链式跑通。**这次验证顺带完整跑通了阶段四附录 E 业务链路在 servedBy 合并部署下的端到端正确性**：`crm-opportunity` 的 `seed-opp-9`（WON）真实触发 `erp-sales` 跨外壳（`go-backoffice`→`go-core`）事件消费自动建单；`seed-opp-11`（信用超限的 WON）真实触发拒绝确认（订单停在 `DRAFT`）+ `infra-workflow` 异常待办，真机查表确认。

版本发布：8 个根组件 + 2 个依赖同步级联，`make gates`/`make version-check` 全绿。⚠️ **现阶段所有环节都在本机跑，不需要 `docker push`**（用户明确说明，本地 build 的镜像 compose 直接能用）。

**结论**：`make tier0`/`make tier1`/`make tier2` 全绿、附录 E 业务链路端到端验证通过、拆回门禁机制在 servedBy 世界下重新可用。

## Task 0.6：`SHELL_CONFIG_JSON` + `be-ops shell-config` 整体退休（2026-09-15~16）

**动机**：`SHELL_CONFIG_JSON`（0.4 收尾那次改动，手工生成内容贴进 configSchema 字符串）有一个真实、反复复发的失败模式——`brickkit.yaml` 一改哪个成员的版本号/config 值/`servedBy` 归属，这份手工维护的数据就会过期，平台不报错，只在外壳真机启动时才炸。写成架构提案反馈给 brickKit（`docs/dev/架构复盘-servedBy落地后的自有改进空间.md`），**brickKit v0.4.2 完整采纳**：新增 `BRICKKIT_SERVED_MEMBERS_CONFIG`（每个成员的完整 config 打包成 JSON 数组原生注入）+ `brickkit up --ignore-served-by`（内存里清空全部 servedBy，验证组件独立启动能力，不写回文件）。

**迁移**：两个外壳仓库的 `main.go`/`main.py` 改成直接解析 `BRICKKIT_SERVED_MEMBERS_CONFIG`；`shellConfigJson`、`be-ops shell-config` 子命令、`internal/shellconfig` 包、`LoadBrickkitConfig`/`MergeConfig`/`ConfigDefaults` 一并删除（产出 4/7/8 至此全部退休）；`teardown-up`/`teardown-down` 改用 `brickkit up --ignore-served-by`，脚本收窄为职责更窄的 `infra/scripts/patch-teardown-bindings.py`（只打资源绑定 + `expose: true` + 禁用 4 个外壳条目，不再碰 `servedBy` 本身）。

**真机踩到的真实 bug（密钥类 config 值撑坏 JSON）**：`brickkit up` 之后 `shell-go-infra` crash-loop，报 `invalid character '\n' in string literal`。根因：`infra/iam-casdoor` 的 `appTokenSigningKeyPem` 等 6 项密钥在 `brickkit.yaml` 里写的是 `${VAR}` 占位符，brickKit 生成 JSON 那一刻完全合法——**问题出在更后面一步**：`docker compose` 读取生成好的 compose 文件时会对整份文件按纯文本做 `${VAR}` 替换，不知道也不关心某个 `${VAR}` 恰好嵌在 JSON 字符串内部，真实密钥（PEM 私钥）自带原始换行符，替换进去直接把 JSON 从中间断开——**这是 `BRICKKIT_SERVED_MEMBERS_CONFIG` 机制本身的普适性设计缺口，不是本项目独有的坑**。

第一次尝试的修补方向（恢复 `envWithProcessFallback` + 6 个密钥类 configSchema 项）真机复测**治标不治本**——真正撑坏 JSON 的是 `infra/iam-casdoor` 自己那条 config 记录，外壳自己多存一份不会让它消失。真正的修复在解析这一步本身：新增 `sanitizeServedMembersConfig`，在 `json.Unmarshal` 之前用最小状态机把字符串**内部**被替换进来的裸控制字符转义回合法形式（合法 JSON 字符串内部不可能出现裸控制字符，见到了就一定是这次替换造成的）。修复后 `envWithProcessFallback`/6 个密钥类 configSchema 项再次删除，回到最初设想的干净形态（`be-shell-go` v0.5.0→v0.5.2、`be-shell-python` v0.3.0→v0.3.2）。

真机验证：`brickkit up` 6 容器全部 healthy（含此前 crash-loop 的 `shell-go-infra`）；`infra-iam-casdoor` 的 JWKS 端点真实返回正确解析出的 RSA 公钥（证明密钥没被截断/损坏）；`make gates`/`make version-check` 全绿；`make teardown-up`/`tier0`/`tier1`/`teardown-down` 全部通过。

### Task 0.6 收尾：brickKit v0.4.3 从根上原生修复（2026-09-16）

反馈文档发出第二天收到 brickKit 回复：没有采纳反馈里给出的两个方向（提前展开 JSON / 转义成 `$$`），而是往下多挖一层根因（Docker Compose 路径刻意不烘焙真实密钥进生成文件，是既有安全原则，不是遗漏），换了一个从根上消除整类问题的方案发回来评审：`BRICKKIT_SERVED_MEMBERS_CONFIG` 的 `config` 字段改名 `configEnvVars`，语义从"key → 值"变成"key → 外壳进程环境里那条独立变量的名字"——每个成员的每个 config 值各自生成一条独立的、带组件 ID 前缀的标量环境变量，`${VAR}` 占位符继续交给 docker compose 自己展开，不再嵌在任何结构化字符串内部，这一整类问题从数据形状上就不存在了。

评审时核实了一个潜在风险点：`EnvPrefix` 不带版本号，"同一个外壳收编同一组件两个版本"场景下 config 值若恰好不同会直接报错——确认这不是新缺陷，是"合并进同一外壳=共享同一个进程环境"本身固有的性质，跟 `*_ENDPOINT` 早就同名共享、靠碰撞检测兜底的行为一致，可以接受（这条判断直接关系到 05b 里"同一外壳收编同一组件两个版本"那条变体该怎么解读结果）。

**迁移**：两个外壳仓库的 `Config`/`config` 字段改名 `ConfigEnvVars`/`configEnvVars`，`buildModules` 从直接读 JSON 里的值改成先读变量名再 `os.Getenv`；`sanitizeServedMembersConfig`（连同回归测试）整个删除——这层下游兜底彻底不需要了。

真机验证：`brickkit up` 6 容器全部 healthy；`docker exec ... echo "$BRICKKIT_SERVED_MEMBERS_CONFIG"` 核对过 `configEnvVars` 里只有变量名、没有任何密钥值；standalone 场景下 `infra-iam-casdoor` 独立容器同样验证过 JWKS 端点；`make gates`/`make version-check` 全绿；`make teardown-up`/`tier0`/`tier1`/`teardown-down` 全部通过。版本发布：`be-shell-go@v0.5.3`、`be-shell-python@v0.3.3`。给 brickKit 的两份一次性反馈/回复文档已删除，问题本身已解决。

**后续小修**：2026-09-16 正式开始 05b 之前的最后一次代码审查又发现一处遗留的失实注释——`shells/go` 的 `cmd/shell/main.go`/`internal/shell/shell.go` 一直声称"`BRICKKIT_SERVED_MEMBERS_CONFIG` 数组顺序 = `brickkit.yaml` 里 `servedBy` 的声明顺序 = 迁移/启动顺序靠它"，真机核对（`docker exec` 核对 go-core 真实生成的数组）+ brickKit 源码核对（`internal/shell/shell.go` 的 `sort.Slice`）确认这是错的：brickKit 自己按 componentId **字典序**排过一遍，跟声明顺序、拓扑序都无关（go-core 的实测对比：声明顺序 `mdm/customer→mdm/product→erp/inventory→erp/finance→erp/sales`，生成顺序 `erp/finance→erp/inventory→erp/sales→mdm/customer→mdm/product`）。这不影响正确性（迁移之间没有跨 schema 外键，`Start()` 用 errgroup 并发跑不依赖顺序），两处注释已改成准确描述，随 `be-shell-go@v0.5.4` 发布，`brickkit.yaml` 3 个 Go 外壳版本同步更新，真机 `brickkit up` 验证 6 容器全部 healthy，`make gates`/`make version-check` 全绿。

## 小结：05b 可以放心依赖的既定事实

1. `servedBy` 是本项目唯一的部署机制，`local: true` 只在临时调试/拆回门禁场景下使用。
2. `BRICKKIT_SERVED_MEMBERS_CONFIG` 承载每个成员的完整装配数据（componentId/version/端口/`configEnvVars`），外壳启动器不需要任何自己生成的平行数据源。
3. 密钥类 config 值从 brickKit v0.4.3 起从数据形状上根治了 JSON 损坏问题，不需要任何下游 sanitizer。
4. `authzBundleUrl`/`iamJwksUrl` 手写字面量机制**必须保留**（依赖边被设计明确禁止），版本升级时需要人工同步，这是已知、可接受的纪律成本，不是待修的坑。
5. `teardown-up`/`teardown-down`（`brickkit up --ignore-served-by` + `patch-teardown-bindings.py`）是验证"组件真的能独立部署"这条设计铁律（§1.5）的标准机制，05b 的"纯独立组件"类任务可以直接复用这套机制起步。
6. 合并部署原生支持 K8s（读源码确认，本项目自己尚未真机验证）——05b Task 6 要补上这个验证。
