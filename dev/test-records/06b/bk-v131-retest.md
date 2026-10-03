# brickKit v1.3.1 复测记录（第二、三轮回复 + 项目级采纳）

## 目标

1. 项目级采纳 brickKit v1.3.1（当前 2.x 组件不动）：`skills update`、`$endpoint:` 地址、项目自己提供的网络、去掉 R39 的 host-gateway 绕法。
2. 按 `brickkit-feedback/replies/phase-06.md` 每条的"复测"，在真机上自己复现能在 Docker 上验的条目；需要 2.x 组件没有的 `component.yaml` 新字段的条目，用 scratch 项目里 `brickkit new` 出来的最小组件验。项目规则："已修复"要自己复现才算关闭。

## 环境

- `brickkit version`：`BrickKit CLI v1.3.1`，`Supported Manifest version: brickkit/v1`，targets docker / podman / k8s；brickKit 源码 HEAD `e0af7092`（tag v1.3.1）
- Docker 29、Compose v2；基础资源 be-postgres / be-nats / be-casdoor / be-rustfs / be-traefik 一直在跑
- 日期 2026-10-03；真实项目 `/home/zhijie/Desktop/github/be-assembly-standard`，起停组件都经 `infra/scripts/project-lock.sh`
- scratch：会话 scratchpad 下 `l1/`（`proj-copy/` 是项目副本，用来删页面、加 TODO；`bk131-scratch/` 是 `brickkit init` 的最小项目，compose 项目名 `brickkit-bk131-scratch`）；结束时容器、镜像 `demo-*`、网络都已删

## 项目级采纳（改了什么）

| 文件 | 改动 |
|---|---|
| `.claude/skills/brickkit-*`（4 个） | `brickkit skills update`：component / deploy / plan-change / troubleshoot 从 v1.1.0 刷到 v1.3.1；assemble 已是最新。`AGENTS.md`、`AGENTS.zh.md` 逐字节未变（维护块已是当前内容，我们自己的小节全部保留） |
| `config/vars.yaml` | `AUTHZ_BUNDLE_URL: $endpoint:infra/authz/authz/bundle`、`IAM_JWKS_URL: $endpoint:infra/iam-casdoor/.well-known/jwks.json`、`IAM_WEBHOOK_CALLBACK_URL: $endpoint:infra/iam-casdoor/api/iam/webhooks/casdoor`（路径都核对过源码：authz `http.go:30`，iam `http.go:29/37`）；手写的版本化服务名全部删掉 |
| `Makefile` | `gates` 去掉 `service-hostname-scan`（裁定 bk1 退役：配置里已没有手写的版本化服务名可查，门禁只会空跑通过），写了注释；帮助文字同步 |
| `deploy.yaml`、`deploy.teardown.yaml` | 顶层 `network: brickkit-be-assembly-standard-net`（沿用原网络名） |
| `infra/docker-compose.infra.yml` | 本来就把该网络声明成 `external`；只改注释（网络由项目提供，不再模仿 brickKit 标签） |
| `infra/scripts/lib.sh` | `ensure_net` 改成普通、幂等的 `network create`，不带任何 compose / brickKit 标签；网络名取 `deploy.yaml` 的 `network:`；`target: podman` 时用 `podman` |
| `infra/scripts/check.sh` | `make check` 多查一行项目网络 |
| `infra/scripts/verify-component.sh` | 删掉 R39 的 host-gateway IP 改写（focus 只 `local on`，`deploy.local.yaml` 照样备份 / 还原） |
| `infra/scripts/teardown-sync.py` | 同步、核对时带上 `network:`（拆回验证也要接项目网络） |
| `infra/scripts/lib/require-brickkit.sh` | 要求版本改成 `BrickKit CLI v1.3.1` |
| `infra/scripts/tests/*` | 版本号跟着改；verify 的 focus 测试改成"不再改写 vars:"；teardown 新增 `network` 用例。11 个脚本测试全绿（`test_verify_deploy.py` 31/31，`test_teardown_sync.py` 8/8） |

`make gates`：exit 0（6 个 be-acceptance 门禁 + docs-boundary + docs-mirror + `brickkit up --dry-run`）。`make teardown-sync CHECK=1`：一致；`brickkit up -f deploy.teardown.yaml --ignore-shells --dry-run`：exit 0。

## lint 现状（`brickkit lint --all --strict`，全量输出，未截断）

exit 1，40 个文件，5 个有错误，11 条警告。全部原因：

- `❌ [MANIFEST_INVALID]` ×5：`components/frontend/standard`（还是 1.x 的 `dependencies.resources`）与 4 个外壳（`shell.members: []`，即 V-03 的老状态）——都在组件 / 外壳仓库里，不属于项目级。
- `⚠️` ×10：`components/frontend/standard` 缺 BRICKKIT.md、AGENTS / README 缺小节、没有维护块——同上。
- `⚠️ [DOC_PLACEHOLDER] a placeholder (后补)`，`docs/zh/04-foundations/07-tenancy.md:92`——这是 **lint 的误报**：原文是"事后补上，就是每个组件一次大版本"，"事后补上"里含"后补"两个字。见下文 F06-011。

项目级的三层文件（`brickkit.yaml` / `deploy.yaml` / cross-file）全部 ✅。组件目录里：`components/erp/sales` 下 `brickkit lint` 与 `--strict` 都是 `🔎 Only erp/sales is checked`、3 个文件 0 警告；`shell/be/go-core` 下只查它自己（报它自己的 `members: []`）。

## 逐条复测

### F06-001 镜像树 / F06-003 AGENTS 译本 → 通过

- 步骤：项目副本里删 `docs/zh/04-foundations/07-tenancy.md`，根 `AGENTS.zh.md` 末尾加一行 TODO，`components/erp/sales/AGENTS.zh.md` 末尾加一行 TODO，`brickkit lint --all --strict`。
- 关键输出：
  ```
  ⚠️ [DOC_PLACEHOLDER] a placeholder (TODO) is still in the text
     File: AGENTS.zh.md
  ⚠️ [DOC_TRANSLATION_DRIFT] this page has no zh version docs/zh/04-foundations/07-tenancy.md: with docs/<lang>/ trees, every page is in every tree
     File: docs/en/04-foundations/07-tenancy.md
  ⚠️ [DOC_PLACEHOLDER] a placeholder (TODO) is still in the text
     File: components/erp/sales/AGENTS.zh.md
  ```
  组件 `AGENTS.zh.md` 已没有占位 `## BrickKit`，真实项目里 `erp/sales` 的 `--strict` 是 0 警告。
- 结论：通过。

### F06-004 只查一个组件 → 通过

`components/erp/sales` 下：`🔎 Only erp/sales is checked (brickkit lint --all checks the whole project)`，3 个文件；`shell/be/go-core` 下：`🔎 Only be/go-core is checked`，外加 `ℹ️ be/go-core is not in brickkit.yaml yet, so it has no configuration to check`；`--all` 查 40 个文件。

### F06-005 `brickkit docs` → 通过

`brickkit docs` 列 110 行页面目录；`brickkit docs 01-three-layers/06-vars-and-var-ref`、`--lang zh 04-shell`、`docs/en/11-reference/03-deploy-yaml-schema.md` 路径形式都能打印。lint 的建议行是 `brickkit docs 11-reference/01-component-yaml-schema (online: https://github.com/brickKit/brickKit/blob/v1.3.1/…)`。

### F06-010 lint 每条带错误码 → 通过

- 英文输出里所有以 `⚠️` / `❌` 开头的行，只有命令失败块的 `❌ Error: the structure check did not pass` 不带 `[码]`（回复里说明了这一块不改）。
- `BRICKKIT_LANG=zh` 再跑一次，按码计数中英文完全相同：`DOC_PLACEHOLDER 1/1`、`DOC_SECTION_MISSING 8/8`、`MANIFEST_INVALID 5/5`、`DOC_FILE_MISSING 1/1`、`AGENTS_BLOCK_MISSING 1/1`。

### F06-009、F06-002、F06-006～008、FR06-002/004/011/016/017/023/024（文档类）→ 通过（文字核对）

`skills update` 之后的 deploy skill 写的是"8080、8081 照常登记，只在本次 up 已分出去时才顺延，`10000 + 容器端口` 要空着"；plan-change skill 第 29 行"决策在项目 `AGENTS.md` 的 `Where to look` 指定的位置"。`brickkit docs` 里逐页找到：`09-patterns/01-component-design` 的黑盒一致性套件（第 6 条）与"后台任务：同一份代码可能同时跑着好几份"，`04-shell/05-shell-development` 的"One process, several members"表与"Metrics"小节，`09-patterns/04-service-calling` 的"Calling over gRPC"，文档规范里可选的 `### Data and retention`，`08-remove-and-archive` 写明数据不动，`07-sensitive-values` 的 `file:///etc/shop/tls.key`，`05-migration/02-env-passthrough` 的 `DB_MIGRATION_HOST`。

### FR06-001 `$endpoint:` → 通过（Docker 真跑；外壳与 K8s 在 scratch 里看生成结果）

- **vars.yaml 一处、13 个组件照旧 `$var:`**：`brickkit up --dry-run` 后 compose 里 `AUTHZ_BUNDLE_URL=http://infra-authz-2-0-1:8223/authz/bundle` 23 处、`IAM_JWKS_URL=http://infra-iam-casdoor-2-0-0:8200/.well-known/jwks.json` 25 处、`WEBHOOK_CALLBACK_URL=http://infra-iam-casdoor-2-0-0:8200/api/iam/webhooks/casdoor` 2 处（服务 + 迁移）；与原手写值逐字相同。
- **authz ↔ iam 互相引用、各自引用自己，不报环**：`up --dry-run` exit 0；`brickkit deps infra/authz`：
  ```
  infra/authz@2.0.1
  └── infra/iam-casdoor@2.0.0 (address from config ($endpoint:))
      └── infra/authz@2.0.1 (cycle)
  Required by: infra/iam-casdoor@2.0.0
  Its address is used in the config of: crm/opportunity@2.0.0, erp/finance@2.0.0, … mdm/product@2.0.0
  ```
  启动顺序里没有 `$endpoint` 带来的 `depends_on`（只有 iam → authz 这条真实依赖）。
- **graph**：`brickkit graph` 里 23 条 `-. $endpoint .->` 虚线，例如 `mdm_customer_2_0_1 -. $endpoint .-> infra_authz_2_0_1`。
- **换成员只改一行**：把 `IAM_JWKS_URL` 改指 `infra/authz`，dry-run 后 25 处全部变成 `http://infra-authz-2-0-1:8223/.well-known/jwks.json`；改回后恢复。
- **报错**：指向项目里没有的组件 → lint 与 up 都报 `❌ [CONFIG_INVALID] … mdm/customer@2.0.1's IAM_JWKS_URL is $endpoint:infra/iam-keycloak/…, but infra/iam-keycloak is not in brickkit.yaml`，建议 `brickkit add`；不存在的端口名 → `… has no extra port named nope / Its extra ports: grpc`。
- **真跑**：全部 13 个组件 `brickkit up` exit 0、13 个 `running (healthy)`；`make verify ID=erp/sales ROUTE=/erp/sales/orders FOCUS=1` 全 PASS，其中"带 dev.superuser 的 token → 200"说明 `IAM_JWKS_URL`、`AUTHZ_BUNDLE_URL` 运行期可用，11 条跨组件测试全 PASS。没有启动顺序的代价也看到了：`infra/workflow` 启动时 authz 还没起，打了一条 `WARN 拉取 authz bundle 失败，沿用内存里已有的旧版本 … lookup infra-authz-2-0-1 … server misbehaving`，之后自动恢复（协议本来就是 fail-static + 重试）。
- **焦点运行带上被引用方**：`up --focus erp/sales` 的状态计算里 `infra/authz`、`infra/iam-casdoor` 都是 starting（没有任何组件 `dependencies` 写它们，是 `$endpoint` 带进来的）；显示的原因是"(erp/inventory needs it)"。
- **本机进程**：`erp/sales` 设成 `mode: debug` 后 `local-debug.erp-sales-2-0-0.env` 里 `AUTHZ_BUNDLE_URL=http://localhost:18223/authz/bundle`、`IAM_JWKS_URL=http://localhost:18200/.well-known/jwks.json`（宿主机映射端口）。
- **外壳托管（scratch）**：`demo/pub` 被外壳 `demo/sh` 托管，`demo/waiter` 的 `PUB_URL: $endpoint:demo/pub/api/pub` 得到 `http://demo-sh-0-1-0:8082/api/pub`（外壳服务名 + 成员自己的端口），容器里实际读到同一个值；`SELF_CALLBACK_URL: $endpoint:demo/waiter/cb` 得到自己的 `http://demo-waiter-0-1-0:8081/cb`。
- **K8s + networkPolicy（scratch 生成）**：外壳的 NetworkPolicy ingress 放 `app: demo-waiter-0-1-0` 进 8082；waiter 的 egress 放行到 `app: demo-sh-0-1-0` 的 8082；Deployment 的 env 是 `PUB_URL=http://demo-sh-0-1-0:8082/api/pub`。
- 结论：通过。本项目当前没有外壳在 `brickkit.yaml` 里（4 个外壳都是 `members: []`），所以"外壳托管 authz / iam"的真跑留到外壳重建之后。

### FR06-010 本机进程的 `host.docker.internal` → 通过

- 步骤：去掉 `verify-component.sh` 的 host-gateway 改写，`make verify ID=erp/sales … FOCUS=1`；另用 `mode: debug` 生成调试 env 对照。
- 关键输出：focus 行 `PASS focus：宿主机 http://localhost:8084/healthz → 200`，本机进程连上了 PG、NATS 与容器里的依赖。`mode: debug` 的 env：
  ```
  PG_HOST=localhost
  NATS_URL=nats://localhost:4222
  ERP_INVENTORY_GRPC_ENDPOINT=http://localhost:19096
  ```
  同一次生成里依赖容器 `erp-inventory-2-0-0` 仍是 `PG_HOST=host.docker.internal`、`NATS_URL=nats://host.docker.internal:4222`，`extra_hosts: [host.docker.internal:host-gateway]`。
- 结论：通过；R39 绕法已删，V-12 关闭。注意：回复里说"看 focus 的 `local-debug.*.env`"——focus 是 `mode: local`，不写这个文件（只有 `mode: debug` 写），见 F06-013。

### FR06-019 项目自己提供的网络 → 通过；V-16 → 通过

- 步骤（`project-lock.sh` 里一个脚本跑完，部署文件只开 authz + iam）：
  1. 断开 Casdoor、删掉网络，`brickkit up`：
     ```
     ❌ Error: the network brickkit-be-assembly-standard-net named in the deploy file does not exist
        Reason: network: in the deploy file says the project provides this network; brickkit only joins it, and never creates or removes it
        Suggestion: Create it first: docker network create brickkit-be-assembly-standard-net
     ```
     （`error_code: CONFIG_INVALID`，在启动任何容器之前停下。）
  2. `make net` → `labels={}`（不带任何标签）。
  3. 组件先起：`brickkit up` exit 0，authz、iam healthy；再重建 Casdoor 容器接进来。
  4. `brickkit down`：网络留下，Casdoor 仍连着（`containers=be-casdoor`）；再 `up` 正常。
  5. 基础资源先 down（停 Casdoor），组件照跑；再起 Casdoor，重新接入。
  6. `down` / `up` 再循环两次，全部 rc=0，网络标签始终为空。
  7. 全量 13 个组件 `up` 时网络上 14 个容器（13 + Casdoor），`down` 后只剩 Casdoor。
- Casdoor 回调（V-16）：每次 `up` 之后从 Casdoor 容器 `wget http://infra-iam-casdoor-2-0-0:8200/healthz` → `HTTP/1.1 200 OK`；用 Casdoor 管理接口建、删一个 `bk131-probe-*` 用户，iam 日志里出现：
  ```
  {"level":"INFO","msg":"http_request","component_id":"infra/iam-casdoor","method":"POST","path":"/api/iam/webhooks/casdoor","status":200,…}
  ```
  Casdoor 的投递有大约 20 秒延迟（建用户 10:07:02，投递 10:07:22），所以第一轮 8 秒窗口里没看到、多等一会都到了——是 Casdoor 自己的投递节奏，与网络无关。
- 外壳那一半（scratch）：项目网络之外起的 `curlimages/curl` 容器加入 `brickkit-bk131-scratch-net` 后，`http://demo-pub-0-1-0:8082/healthz`（成员别名）与 `http://demo-sh-0-1-0:8082/healthz`（外壳服务名）都是 `ok 200`。
- 结论：通过。`infra/scripts/lib.sh` 不再模仿 brickKit 的内部标签。

### FR06-025 孤立的 `requiredBy` 版本 → 通过

scratch：`demo/ready` 源码升到 0.2.0，`brickkit upgrade demo/ready@0.2.0`（`demo/waiter` 仍钉 0.1.0）→ `brickkit.yaml` 有 `demo/ready 0.2.0` 与 `demo/ready 0.1.0 requiredBy: [demo/waiter]`；然后只改 waiter 的依赖为 `@0.2.0`、版本不变：
```
ℹ️ demo/ready@0.1.0 is in the project only for demo/waiter, and by their current component.yaml none of them depends on it any more — brickkit remove demo/ready@0.1.0 takes it out
```
`brickkit upgrade demo/waiter` 不动文件（版本没变，符合回复）；`brickkit remove demo/ready@0.1.0` 之后 `brickkit.yaml` 只剩 `demo/ready 0.2.0`，提示消失，`up --dry-run` exit 0。`brickkit deps` 不给这条提示（回复只承诺 lint）。

### FR06-026 本地源版本与钉住版本不同（V-07）→ 通过

scratch：`demo/waiter` 源码改成 0.1.1、不 upgrade：
```
ℹ️ demo/waiter: the source in components/demo/waiter is version 0.1.1, but the project pins 0.1.0 and keeps running that one — brickkit upgrade demo/waiter@0.1.1 moves the project to the source's version
```
在组件目录里只查它时同样出现（`the source in . is …`）；`ℹ️` 不计入 `--strict` 的警告数。

### FR06-027 deploy.yaml 在复制之后改过（V-09）→ 通过

scratch：`brickkit local on`；只在 `deploy.yaml` 末尾加一行注释 → `up --dry-run` 不提示；把 `demo/waiter` 加 `replicas: 2` →
```
ℹ️ deploy.yaml has changed since deploy.local.yaml was copied from it, and those changes are not in effect here: brickkit local refresh brings them in (and lists your local changes, to put back)
```
`brickkit local status` 也给同一行；`brickkit local refresh` 之后不再提示。

### FR06-005 事件声明 → 通过（scratch）

- `brickkit graph`：`demo_ready_0_1_0 -.->|"demo.ready.*"| demo_waiter_0_1_0`。
- `brickkit deps` 末尾：
  ```
  Events (publisher → subscriber):
    demo.pub.created.v1: demo/pub@0.1.0 → (no subscriber in this project)
    demo.ready.started.v1: demo/ready@0.1.0 → demo/waiter@0.1.0
    nobody.publishes.this.v1: (no publisher in this project) → demo/waiter@0.1.0
  ```
- lint：`ℹ️ demo/waiter@0.1.0 subscribes to nobody.publishes.this.v1, which no component in this project publishes …`；订阅写成 NATS 的 `demo.ready.>` → `❌ [MANIFEST_INVALID] events.subscribes[0]: not a subscription ("demo.ready.>") …`。
- 本项目 ≥4 段的主题名是不透明字符串，规则兼容（裁定 bk5）；13 个组件补声明留给 3.0.0。

### FR06-006 readinessCheck → 通过（scratch 真跑）

`demo/ready`（Python，`/readyz` 前 20 秒答 503）声明 `readinessCheck: {type: http, path: /readyz}`，`demo/waiter` 强依赖它：
- compose：ready 的 healthcheck 探 `http://127.0.0.1:8080/readyz`，waiter `depends_on: demo-ready-0-1-0: service_healthy`。
- 真跑轮询：`12:12:58 ready=starting waiter=created` → `12:13:23 ready=healthy waiter=running`；ready 的健康日志 10:13:01–10:13:16 rc=1，10:13:22 rc=0；waiter `StartedAt 10:13:22.28`——就绪后才启动。
- K8s 生成：`readinessProbe` 探 `/readyz`，`livenessProbe` / `startupProbe` 探 `/healthz`。
- K8s 两副本滚动更新"客户端看不到 503"没有集群可跑，留给 06e。

### FR06-008 端口协议 → 通过（K8s 生成）

Service：`- appProtocol: http / name: http / port: 8080`、`- appProtocol: grpc / name: grpc / port: 9090`；部署文件写 `k8s.appProtocols: {grpc: kubernetes.io/h2c}` 后变成 `appProtocol: kubernetes.io/h2c`。Docker 下不生成任何东西。网格上按请求分流没验（回复也说明了）。

### FR06-009 stopGracePeriodSeconds → 通过（scratch 真跑）

`deployment.stopGracePeriodSeconds: 25` → compose `stop_grace_period: 25s`；K8s `terminationGracePeriodSeconds: 25`，部署条目覆盖成 40 → `40`。真跑 `brickkit down` 用时 15.6 秒，容器日志：
```
10:13:30 demo/ready SIGTERM: draining for 15.0 s
10:13:45 demo/ready drained, exiting
```
（compose 默认 10 秒会在 drained 之前强杀。）

### FR06-012 mount: file → 通过（scratch 真跑）

- `docker inspect` 的 Env 只有 `SIGNING_KEY_FILE=/run/brickkit/secrets/demo-ready-0-1-0/SIGNING_KEY_FILE`，值不在 env 里；容器里读到 `value=key-v1`。
- 改 `.secrets/signing.key` 为 `key-v2`：先 `up --dry-run`，容器仍读到 `key-v1`（dry-run 不写）；再 `up`，容器 ID 与 `StartedAt` 不变、`restarts=0`，读到 `key-v2`。
- 宿主机 `.brickkit/generated/secrets/` 是 `drwx------`，下面的目录 `drwxr-xr-x`、文件 `-rw-r--r--`，与回复一致。
- K8s 生成：env 只有路径，Secret 卷挂到 `/run/brickkit/secrets/demo-ready-0-1-0`，只有 mount: file 密钥的组件**不带** `brickkit.io/secret-digest`；经 env 读密钥的 `demo/waiter` 带注解，密钥值 t1 → t2 时摘要从 `f454033ea830c2cc` 变成 `7a4dabbd3105a87b`（v1.3.1 的 `e0af7092`）。
- Podman / SELinux 没验（裁定 bk4 已写明）。

### FR06-015 按路径分流 → 通过（K8s 生成）

两个组件共用 `app.example.com`，`paths: [/api/pub]` 与 `[/api/waiter, /webhooks/waiter]`：生成 `ingress/demo-pub.yaml`、`ingress/demo-waiter.yaml`（名字是 `<scope>-<name>`，不带版本，裁定 bk13），`pathType: Prefix`。两条相同路径 → `❌ Error: app.example.com/api/pub is routed to more than one component`；`tlsSecret` 不一致 → `❌ Error: the entries sharing domain app.example.com don't name the same tlsSecret`。Docker 下 `paths` / `hostname` 给 `⚠️ … has no effect with target: docker and is ignored`。Traefik 那条路（labels）本轮没跑。

### FR06-021 外壳代成员 expose → 通过（scratch 真跑）

外壳 `demo/sh` 托管 `demo/pub`，成员条目 `expose: true, exposePort: 28182`：外壳服务 `ports: ['28182:8082']`，网络别名 `demo-pub-0-1-0`；真跑后宿主机 `curl http://localhost:28182/healthz` → `ok 200`，`docker ps` 显示 `0.0.0.0:28182->8082/tcp`。K8s：成员有自己的 Ingress `demo-pub`（host `pub.example.com`），指向成员 Service `demo-pub-0-1-0`，后者 `selector: app: demo-sh-0-1-0`。

### 健康检查探 127.0.0.1（`e69289be`）→ 通过（scratch 真跑）

三个 Python 组件都只监听 `0.0.0.0`（IPv4），镜像 `python:3.12-alpine`：compose 的检查是 `wget -q --spider http://127.0.0.1:<port>/…`，三个都 `healthy`。对照：同一容器里 `wget http://localhost:8082/healthz` → `Connection refused`（Alpine 先解析到 `::1`）——旧的 `localhost` 写法在这里会一直不健康。

### V-11 `add` 把已有成员挪进外壳 → 成立（新缺陷 F06-012）

scratch：`demo/pub` 先在项目里，再 `brickkit add --local` 一个 `shell.members: [demo/pub@0.1.0]` 的外壳：
```
➕ Adding demo/sh@0.1.0
   ✅ demo/sh@0.1.0
   🔗 demo/pub moved into shell demo/sh
```
`deploy.yaml` 里 `demo/pub` 从顶层挪到了 `demo/sh` 的 `members:` 下。而 `brickkit docs 04-shell/04-members-management`（v1.3.1，中英文）写的是"项目里本来就有、后来才出现能承载它的外壳的组件，`add` **不会**替你把它挪进外壳，也不会问你要不要挪"。

## 新发现的问题

| 编号 | 一句话 | 证据 |
|---|---|---|
| F06-011 | 中文占位词按字面子串匹配：正文里的"事后补上""以后补充"被报成 `DOC_PLACEHOLDER (后补)` | 真实项目 `docs/zh/04-foundations/07-tenancy.md:92`；scratch README 两行最小复现；源码 `internal/doccheck/common.go` 的 `containsWord` 对中文直接 `strings.Contains` |
| F06-012 | `add` 外壳时把已有组件挪进外壳（`🔗 … moved into shell`），与 `04-shell/04-members-management` 写的"不会挪"相反 | 上一节 V-11 |
| F06-013 | `mode: local`（含 focus）的迁移提示让人"用 `local-debug.<服务名>.env` 里的变量"，但这个文件只在 `mode: debug` 时写 | 真实项目 focus erp/sales 与 scratch focus demo/waiter 都打印该提示，`.brickkit/generated/` 下都没有 `local-debug.*.env`；源码 `up.go` 的 `writeLocalEnvFiles` 只写 `ModeDebug` |
| F06-014 | deploy skill 的值写法示例 `IAM_URL: $endpoint:infra/iam/.well-known/jwks.json`：键名是基地址键，值却带 JWKS 路径 | `.claude/skills/brickkit-deploy/SKILL.md`（v1.3.1）；`brickkit docs 01-three-layers/06-vars-and-var-ref` 的示例是 `IAM_URL: $endpoint:infra/iam-casdoor` 与 `IAM_JWKS_URL: …/.well-known/jwks.json` 分开写 |

## 没有复测的

- FR06-022、028（暂缓）与 FR06-007、013、014、018、020、029（不做）：没有可复测的东西；FR06-013 的替代做法已在裁定 bk10 吸收。
- K8s 真集群上的项（两副本滚动无 503、gRPC 网格分流、Ingress 改名的原地切换、Pod 因密钥摘要滚动）：本轮只看生成结果，06e 部署矩阵再跑。
- 外壳托管 authz / iam 的真跑：项目里还没有可用的外壳（`members: []`）。
- V-08（外壳成员指标）：只验到"成员别名 + 成员端口从网络里可达"，没有开 Prometheus 抓取。
