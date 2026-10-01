# BrickEnterprise 部署手册

*[English](../en/deployment-handbook.md)*

> **给部署人员。你只需要这一份。** 不需要读设计书，也不需要读任何组件文档——需要你去看别处时，本手册会指名道姓地告诉你看哪一节。
>
> 遇到本手册没写、或者照着做跑不通的情况：**那是本手册的 bug，不是你的**。记下来反馈，我们改它（`docs/README.md` 的「所有文档都可以改」）。
>
> 想定制/换掉某个功能，先看 [`_replaceability-map.md`](_replaceability-map.md)——什么可以换、换了牵连谁，一张图一张表说清楚。

## 本手册当前覆盖到哪

| 部分 | 状态 |
|---|---|
| 一、宿主机准备 | ✅ 可用 |
| 二、基础资源（10 个带外容器） | ✅ 可用（`make up` 已实现） |
| 三、数据库：谁建什么 | ✅ 可用 |
| 四、业务组件：部署前必须准备的东西 | ✅ 可用（14 个组件全部出档，真机验证过） |
| 五、外壳合并部署 / K8s | ✅ 可用（12 种拓扑×环境基础组合全部真机验证通过，外壳+K8s 现在是原生能力——详细选型说明见 [`deployment-selection-guide.md`](deployment-selection-guide.md)，本节只给关键结论） |
| 六、升级与回滚 | 🔜 有第一个客户时 |

---

## 一、宿主机准备

### 1.1 软件

| 要求 | 怎么确认 |
|---|---|
| Docker Engine ≥ 24 | `docker --version` |
| Docker Compose v2（**不是 `docker-compose` 老版**） | `docker compose version` |
| 当前用户能用 docker（在 `docker` 组里，或用 sudo） | `docker info` 不报权限错 |

### 1.2 ⚠️ 宿主机端口必须空着，这是最常见的第一个坑

下面这些端口**任何一个被占用，对应容器都起不来**。而症状往往指向别处：Compose 报 `port is already allocated`，或者更糟——容器起来了但连的是别人的服务。

```bash
# 一条命令查全部（有输出 = 有冲突）
for p in 5432 4222 8222 80 443 28080 8000 9000 3000 3100 3200 4317 4318 13133 29090; do
  ss -ltn 2>/dev/null | grep -q ":$p " && echo "被占用: $p"
done
```

| 端口 | 谁要用 | 必需? |
|---|---|---|
| 5432 | PostgreSQL | ✅ |
| 4222, 8222 | NATS（客户端 / 监控） | ✅ |
| 80, 443, 28080 | Traefik（HTTP / HTTPS / Dashboard） | ✅ |
| 8000 | Casdoor | ✅ |
| 9000 | RustFS 对象存储 | ✅ |
| 3000, 3100, 3200, 4317, 4318, 13133, 29090 | 可观测性五件套 | ❌ 只在开可观测性时 |
| 9001 / 28081 / 29092 / 5672,15672 | MinIO / Keycloak / Kafka / RabbitMQ 替换件 | ❌ 只在换实现时 |

**冲突了怎么办**：先查是谁占的（`docker ps` 看有没有别的项目的容器；`ss -ltnp` 看进程），停掉它，或者找我们改端口。
⚠️ **不要自己改 compose 里的端口**——端口册（`registry/ports.tsv`）是全局唯一且**只增不改**的，私自改会在后面装组件时撞车，而那时报错指向的是组件不是端口。

### 1.3 磁盘与网络

- 数据全部落在 Docker 具名卷里（`pg_data` / `nats_data` / `rustfs_data` …），**不要用 `docker volume prune`**
- 本地化部署**不需要外网**，但**首次装机要拉镜像**，得有一次联网机会（或提前 `docker load` 离线包）

---

## 二、基础资源

### 2.1 三步起来

```bash
# ① 创建共用网络
make net

# ② 准备密码文件
cp .env.example .env
#    ⚠️ 逐行改成真值，不要留 change_me。这个文件不进 Git，
#    但它会留在客户机器上——它就是这套系统的密码本。

# ③ 一键开启默认的 5 个容器（先整体预检，全过才启动；已就绪的会跳过）
make up
```

`make up` 内部分三段：预检 → 启动 → 复检，结尾就是 §2.1 完整跑完后你会看到的 `make check` 那张表。**预检发现任何一个默认资源"不对"（镜像/端口/健康不符，或端口被占）就会整体拦下，一个容器都不启动**——不会有"起了一半"的状态。

`make up` 之后随时可以单独查状态：

```bash
make check     # 只查默认 5 个
make status    # 看 docker compose ps 的原始视图
make down      # 全部停止（不删数据）
```

⚠️ **`make up` 不会替你处理"不对"的资源，也不会替你 stop/rm 任何容器。** 报错信息会点名是谁、哪里不对；排查完之后重新跑 `make up` 就行，它对已经健康的容器是幂等的（不会重启、不会重建）。

⚠️ **`--env-file .env` 这件事你不需要操心**——`make` 目标已经把它接好了。只有你打算绕开 `Makefile`、自己手写 `docker compose` 命令时才要记得带上；省了的症状是：

```
required variable POSTGRES_PASSWORD is missing a value
```

看起来像 `.env` 写错了，其实是 compose 去 `infra/.env` 找了（Compose 把"第一个 `-f` 指向的文件所在目录"当项目目录）。**也不要用 `--project-directory .` 去"修"它**——`./traefik/traefik.yml`、`./casdoor/conf` 这些相对挂载会跟着去仓库根找，而 Docker 对不存在的挂载源会默默建一个空目录，于是 Traefik 拿着空配置照样 healthy、只是什么都不路由。

### 2.2 默认起哪 5 个

| 容器 | 是什么 | 健康的样子 |
|---|---|---|
| `be-postgres` | PostgreSQL 16，全系统唯一的库 | `docker inspect -f '{{.State.Health.Status}}' be-postgres` → `healthy` |
| `be-nats` | 事件总线（JetStream 已开） | 同上 |
| `be-traefik` | API 网关 | 同上；Dashboard <http://localhost:28080> |
| `be-casdoor` | 登录与身份（**首次启动约 30–60 秒**，它要建 44 张表） | `curl -fsS http://localhost:8000/api/health` → 200 |
| `be-rustfs` | 对象存储 | 同上 |

### 2.3 可观测性五件套（可选，要就整套）

```bash
make obs-up      # 开启
make obs-down    # 关闭
```

**不开也能跑**——组件在拿不到 OTel 地址时会静默丢弃遥测，不会阻塞业务（设计书 §7.5）。资源紧张的客户机器上可以不开。

⚠️ **`be-otel` / `be-loki` / `be-tempo` 三个容器没有 Docker 层面的健康检查**（它们的镜像里没有 shell，物理上做不到容器内自检）。`make obs-up` 只等它们进入运行状态就会返回，**不代表它们已经能收数据**。想确认，从宿主机侧查：

```bash
curl -fsS http://localhost:13133/            # otel-collector
curl -fsS http://localhost:3100/ready        # loki（见下面 ⚠️）
curl -fsS http://localhost:3200/ready        # tempo
```

⚠️ **`be-loki` 启动后头 15 秒左右 `/ready` 会返回 503**（`"Ingester not ready: waiting for 15s after being ready"`）——**这是 Loki 自己的正常行为，不是故障**，等一会儿再查就是 `ready`。

### 2.4 替换件（换掉某个默认实现）

```bash
make minio-up      # 对象存储 → MinIO（会自动检查 rustfs 是否还在跑，跑着就拦下）
make keycloak-up   # 身份 → Keycloak（会自动检查 casdoor）
make kafka-up      # 事件总线 → Kafka
make rabbitmq-up   # 事件总线 → RabbitMQ
make nginx-up      # 网关 → Nginx
# 对应的 make <name>-down 关闭
```

| 换什么 | 命令 | ⚠️ |
|---|---|---|
| 对象存储 → MinIO | `make minio-up` | 与 `rustfs` 同一个「storage」互斥组，两者不能同时跑 |
| 身份 → Keycloak | `make keycloak-up` | 与 `casdoor` 同一个「iam」互斥组 |
| 事件总线 → Kafka / RabbitMQ | `make kafka-up` / `make rabbitmq-up` | 与 `nats` 同一个「mq」互斥组。⚠️ **这个不是「换个容器」那么简单**，还要改所有组件的 Manifest。**不要自己做，找开发** |
| 网关 → Nginx | `make nginx-up` | 与 `traefik` 同一个「gateway」互斥组 |

⚠️ **不需要你自己先手动停旧的那个。** `make <替换件>-up` 会自动检查同一个互斥组里有没有别的成员在跑，跑着就直接报错（不会帮你停），报错信息里会点名是谁、该跑哪条命令去关它。见 §六故障表。

---

## 三、⭐ 数据库：谁建什么，哪些自动哪些要你做

这是本手册最要紧的一节。**分成五层，只有第 3、4 层需要你动手，而且只有一次。**

| # | 建什么 | 谁建 | 什么时候 | 要你做吗 |
|---|---|---|---|---|
| 1 | `brickkit_db` 这个 database | `infra/postgres/initdb/00-bootstrap.sql` | `be-postgres` **首次**启动 | ❌ 自动 |
| 2 | `casdoor` / `keycloak` 两个 schema | 同上 | 同上 | ❌ 自动 |
| 3 | **62 个组件各自的 schema + `_archive` + PG role + 授权** | `be-ops` 生成的建置脚本 | **装业务组件之前** | ✅ **要你执行一次** |
| 4 | **5 个外壳登录角色** | 同上 | 同上 | ✅ 同上 |
| 5 | 每个组件自己的业务表 | 该组件的 migration | 组件每次启动 | ❌ 自动 |

第 3、4 层的具体命令：

```bash
make db-init   # 幂等、可重跑；建的是 brickkit_db（演示/生产库），不是 make test-db-init 建的 brickkit_test_db
```

内部做的事：跑 `be-ops db-script` 生成一份建库 SQL（62 个组件的 schema + `_archive` + PG role + 5 个外壳登录角色，全部 `IF NOT EXISTS`/`DO` 块包一层，可以放心重跑），再用 `.env` 里的 5 个 `SHELL_*_PASSWORD` 变量把外壳登录角色的密码塞进去执行。**必须在装任何业务组件之前跑一次**，且必须在 `.env` 已经填好真值之后跑（§2.1 第 ② 步）——`SHELL_*_PASSWORD` 五个变量如果还是 `.env.example` 抄来的 `change_me_...`，建出来的角色密码就是那几个占位字符串，之后想改密码要手动 `ALTER ROLE`，不会因为你后来改了 `.env` 而自动跟着变。

### 3.1 为什么不能全自动一步到位

因为**平台（brickKit）自己不建库**：建库需要 `CREATEDB` 权限，而让每个组件的运行期账号都带着它，等于全平台提权。所以 `brickkit up` 只会**打印**出需要预先创建的语句，实际动作由我们的工具链做（设计书 §2.7.2）。

第 1、2 层之所以能自动，是因为它们走的是 PostgreSQL 官方的 `docker-entrypoint-initdb.d` 机制——**但那个机制只在数据卷为空时跑一次**。

### 3.2 数据卷不是空的（比如重装、或换了 compose）

第 1、2 层不会重跑。手动补上：

```bash
docker exec -i be-postgres psql -U postgres < infra/postgres/initdb/00-bootstrap.sql
```

`CREATE DATABASE brickkit_db` 那一句会报「已存在」，**忽略即可**，后面两句 `CREATE SCHEMA IF NOT EXISTS` 是幂等的。

### 3.3 确认这一层没问题

```bash
docker exec be-postgres psql -U postgres -lqt | cut -d\| -f1 | grep -w brickkit_db
docker exec be-postgres psql -U postgres -d brickkit_db -Atc \
  "select nspname from pg_namespace where nspname in ('casdoor','keycloak') order by 1"
```
期望：第一条打印 `brickkit_db`；第二条打印两行 `casdoor` / `keycloak`。

---

## 四、⭐ 业务组件：部署前必须准备的东西

14 个组件已经全部出档、真机验证过。跑 `brickkit up` 之前，**有几项配置必须由你（部署人员）提供真实值，平台/组件本身不会替你生成**——漏了哪一项，症状不总是"起不来"：有的会直接拒绝启动（`brickkit up --dry-run` 就报错），有的组件会正常 `healthy` 但某个具体功能悄悄坏掉，不查这份清单很难联想到根因。

### 4.1 起业务组件的流程

在 §三 的 5 层数据库准备好、`.env` 也按下面 4.2 填完真值之后：

```bash
make db-init          # 先跑一次（§三），幂等
brickkit up --dry-run # 先看一遍会起哪些、什么顺序，不会真的启动
brickkit up            # 真的启动
```

`.env` 里的值是怎么进到组件里的：`brickkit.yaml` 每个组件的 `config:` 块里，凡是写成 `"${某变量名}"` 的，`brickkit up` 生成 compose 时会原样从 `.env` 里取值替换；不是 `${...}` 形式的（比如 `defaultWarehouseId: "1"`）是直接写死的业务配置，不走 `.env`。

### 4.2 必须真实处理的项——按组件分组的清单

⚠️ **下面这份清单只列"缺了会导致启动失败，或导致某个具体功能悄悄失效"的项**——`component.yaml` 里还有一些字段没写 `default:` 但缺了并不会出问题（比如 `iamJwksUrl`/`authzBundleUrl`，缺了只是把对应权限判定降级成 fail-closed 403 / 503，不会阻止组件启动；这两项本仓库已经在 `brickkit.yaml` 里全部接好，不需要你再管）。这个区分本身就是这份仓库自己"第 18 条易错项"点名过的坑——`configSchema` 里"没写默认值"不等于"真的必填"，唯一准的判据是代码里是不是用了 `MustString`/`Int`（会 panic）。

| 组件 | 配置项 | `.env` 变量名 | 这是什么、从哪儿来 |
|---|---|---|---|
| `erp/sales` | `defaultWarehouseId` | （不走 `.env`，`brickkit.yaml` 里直接写死 `"1"`） | 一个真实存在于 `erp-inventory` 的仓库 ID。本仓库的种子迁移已经播种了 `id=1`（`WH-EAST`），**装这个标准装配就不用改**；如果你自己改过 `erp-inventory` 的迁移、这个仓库 ID 不是 `1`，要同步改这里 |
| `integration/im-dingtalk` | `dingtalkAppKey`<br>`dingtalkAppSecret`<br>`dingtalkAgentId` | `DINGTALK_APP_KEY`<br>`DINGTALK_APP_SECRET`<br>`DINGTALK_AGENT_ID` | 真实钉钉"企业内部应用"凭据（见 4.3 的注册步骤）。不填就是占位值，**组件仍能正常启动**，只有真的调钉钉 API 那一步（工作通知）会失败 |
| `infra/iam-casdoor` | `casdoorBaseUrl` | （不走 `.env`，`brickkit.yaml` 里直接写死） | 带外 Casdoor 容器的地址。标准装配固定是 `http://host.docker.internal:8000`（Casdoor 由 `docker-compose.infra.yml` 起，宿主机映射端口 8000）——**只要你没改过 Casdoor 的宿主机端口映射，这一项不用动** |
| `infra/iam-casdoor` | `casdoorAdminPassword` | `CASDOOR_ADMIN_PASSWORD` | Casdoor 内置 `admin` 账号的**真实密码**（见 4.4，这项不会自动帮 Casdoor 改密码，是反过来要跟 Casdoor 的真实密码对上） |
| `infra/iam-casdoor` | `webhookSharedSecret` | `WEBHOOK_SHARED_SECRET` | 一个你自己发明的共享密钥（见 4.4） |
| `infra/iam-casdoor` | `appTokenSigningKeyPem` | `APP_TOKEN_SIGNING_KEY_PEM` | 一把你自己生成的 RSA 私钥，PEM 格式（见 4.4——这是你这次问的那把 RSA 密钥） |
| `frontend/standard` | `iamIssuerUrl` | （不走 `.env`，`brickkit.yaml` 里直接写死） | Casdoor 面向浏览器的**真实公网地址**。仓库里现在是本地开发占位值 `http://localhost:8000`，正式部署前必须换成客户环境的真实域名（见 4.5） |
| `frontend/standard` | `casdoorClientId` | （不走 `.env`，`brickkit.yaml` 里直接写死） | `brickkit-app` 这个 Casdoor 应用的 OIDC 公开 `client_id`（不是密钥，但必须真的去 Casdoor 里查，不能瞎编）。**现在是空字符串——这是一个真实存在、你必须在部署时补上的缺口**，而且只能在 `infra-iam-casdoor` 第一次启动、自己把 `brickkit-app` 建出来之后才查得到（见 4.5） |

### 4.3 钉钉凭据怎么拿

去 <https://open.dingtalk.com> 用手机号注册（免费个人团队即可，不需要真实企业营业执照）→ 建一个"企业内部应用"→ 应用详情页能直接看到：

- **Client ID**（旧称 AppKey）→ 填 `DINGTALK_APP_KEY`
- **Client Secret**（旧称 AppSecret）→ 填 `DINGTALK_APP_SECRET`
- **AgentId**（纯数字）→ 填 `DINGTALK_AGENT_ID`

### 4.4 `infra-iam-casdoor` 三项密钥怎么生成/核对

```bash
# ① webhookSharedSecret：随便一个足够随机的字符串，跟哪个 Casdoor 应用/组织都无关，
#    纯粹是本组件和 Casdoor webhook 之间自己约定的密码
openssl rand -base64 24

# ② appTokenSigningKeyPem：RSA 私钥，PKCS8 PEM——⚠️ 这把钥匙必须你自己生成，
#    组件代码里刻意不会自动生成（合并部署时多个模块共享一个进程，自动生成
#    会导致每次重启都换一把钥匙，等于每次重启强制全员登出）。
#    生成一次，长期使用，妥善保管（同数据库密码一个级别）：
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048
#    输出直接整段拷进 .env 的 APP_TOKEN_SIGNING_KEY_PEM，多行内容要用双引号包起来。
#    需要轮换时看 `appTokenPreviousPublicKeyPem` 那一项——旧公钥留一段时间，
#    旧 token 在 TTL 内还能验签，不是一换就全员登出（component.yaml 里有完整注释）。

# ③ casdoorAdminPassword：这项不是"你发明一个密码"，是反过来要跟 Casdoor
#    的真实 admin 密码对上——Casdoor 官方镜像内置账号是 admin/123（首次
#    启动自带的种子数据，不是本仓库设的）。如果你没有登录 Casdoor 改过这个
#    密码，.env 里写 123 就对；如果你已经在 Casdoor 管理界面（http://localhost:8000）
#    把 admin 密码改掉了，.env 的 CASDOOR_ADMIN_PASSWORD 必须同步改成新密码，
#    两边对不上的症状是 infra-iam-casdoor 日志里出现
#    "登录 Casdoor 管理 API 失败"（不会让整个组件崩掉，但组件自举、
#    gRPC BatchGetUsers 都会用不了，见 §六故障表）。
```

### 4.5 有先后顺序、绕不开手动一步的两个例外

**`frontend/standard` 的 `casdoorClientId`**——这项**只能在 `infra-iam-casdoor` 第一次真的启动之后**才查得到，因为 `brickkit-app` 这个 Casdoor 应用是 `infra-iam-casdoor` 自己在 `Start()` 里自举建出来的，不是提前存在的。所以正式部署要走两轮：

1. 先 `brickkit up` 一次（`frontend/standard` 这时候 `casdoorClientId` 是空的，登录页会坏，其余组件不受影响）。
2. 登录 Casdoor 管理界面（`http://<casdoorBaseUrl>`，账号密码见 4.4）→ Applications → 找到 `brickkit-app` → 复制 Client ID。
   - 或者用 API 现查（需要先登录拿到 session cookie，`<CASDOOR_ADMIN_PASSWORD>` 替换成真实密码）：
     ```bash
     curl -c /tmp/casdoor-cookies.txt -s -X POST http://localhost:8000/api/login \
       -H "Content-Type: application/json" \
       -d '{"application":"app-built-in","organization":"built-in","username":"admin","password":"<CASDOOR_ADMIN_PASSWORD>","autoSignin":true,"type":"login"}'
     curl -b /tmp/casdoor-cookies.txt -s "http://localhost:8000/api/get-application?id=admin/brickkit-app" | grep -o '"clientId":"[^"]*"'
     ```
3. 把查到的 `client_id` 填进 `brickkit.yaml` 里 `frontend/standard` 的 `casdoorClientId`，`brickkit up` 重新部署这一个组件。

**`infra-iam-casdoor` 的 `webhookCallbackUrl`**——这项本仓库已经接好了本机开发环境的值，但**换一台机器部署，这个值大概率要重算**，因为它是 `be-net` 这个 Docker 桥接网络的网关 IP（不是固定的 `172.18.0.1`，取决于这台机器上网络的创建顺序），查询命令：

```bash
docker network inspect be-net --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}'
```

拿到的网关 IP 拼上 `infra-iam-casdoor` 的宿主机映射端口（标准装配是 `8200`）和固定路径 `/api/iam/webhooks/casdoor`，就是这一项该填的值。

### 4.6 正式给客户部署前，再确认一遍这几项本地开发占位值都换掉了

| 占位值 | 在哪 | 换成什么 |
|---|---|---|
| `CASDOOR_ADMIN_PASSWORD=123` | `.env` | 真实客户环境要改掉 Casdoor 的 admin 密码，两边同步改 |
| `iamIssuerUrl: http://localhost:8000` | `brickkit.yaml` | 客户环境 Casdoor 真实能被浏览器访问到的域名 |
| `webhookCallbackUrl` 里的 `172.18.0.1` | `brickkit.yaml` | 用 4.5 的命令在目标机器上现查 |
| 5 个 `SHELL_*_PASSWORD` | `.env` | 换成真实随机密码（`openssl rand -base64 24`），且要在 `make db-init` 之前改好——建库之后再改 `.env` 不会自动同步到已经建好的 PG role |

---

## 五、外壳合并部署 / K8s

**⚠️ 部署有两个独立的选择维度：拓扑（组件怎么分组）和环境（跑在哪），两者任意组合出 12 种部署形态，全部真机验证过。这里只给最关键的结论和一张速查表；每种形态具体是什么、什么时候该选它、好处代价各是什么、真机踩过哪些坑——完整介绍在专门的 [`deployment-selection-guide.md`](deployment-selection-guide.md)，先看那份文档想清楚要选哪种，再回来看下面怎么操作。**

| 拓扑 \ 环境 | 本地裸进程 | Docker | K8s | Docker+本地混合 |
|---|---|---|---|---|
| **纯独立组件**（不用外壳） | ✅ | ✅ | ✅ | ✅ |
| **纯外壳**（`servedBy` 全量合并） | ✅ | ✅ | ✅ | ✅ |
| **组件+外壳混搭**（本仓库当前真实形态） | ✅ | ✅ | ✅ | ✅ |

**⚠️ 最值得知道的一件事：外壳合并部署 + K8s，现在是 brickKit 原生支持、真机验证通过的能力。** 早期文档说过"K8s 意味着先把所有外壳拆回独立容器，没有部分合并部分上 K8s 这种中间态"——这个说法已经**过时**：现在合并进外壳走的是 brickKit 原生的 `servedBy` 字段，跟 K8s 完全兼容。`local: true`（本机裸进程调试单个组件，不是 `servedBy`）依然不能跟 K8s 一起用，这条限制没有变。

**本仓库当前的真实部署形态**是"组件+外壳混搭"（上表第三行）——11 个 Go 组件 + `infra/print` 合并进 4 个外壳（`go-core`/`go-backoffice`/`go-infra`/`py-render`），`infra/bff-mobile`/`frontend/standard` 结构性地无法合并（前者按设计保持独立，后者是纯前端 SPA/H5，压根没有可以合并的后端进程），继续独立部署。§3、§4 前面几节讲的"14 个组件"就是这个真实形态。

**`servedBy` 怎么工作、K8s 部署要注意什么、多版本共存哪些场景成立、这几年真机踩过哪些已经修复的坑**——这几件事的完整说明全部在 [`deployment-selection-guide.md`](deployment-selection-guide.md)，不在这里重复。

### 5.1 常见配置错误速查

下面这些错误全部真机触发过，报错都在 `brickkit up --dry-run` 阶段直接拦下（不会生成错误的部署文件、也不会等到真的启动才失败），错误码统一是 `CONFIG_INVALID`：

| 错误配置 | 报错阶段 | 报错要点 |
|---|---|---|
| `servedBy` 没写 `@版本`（格式错误） | 结构校验（最先） | 指出正确格式 `<组件ID>@<精确版本>` |
| `servedBy` 指向自己 | 结构校验 | "不能指向自己" |
| 外壳 A `servedBy` 外壳 B，B 自己又 `servedBy` 别的外壳（链式嵌套） | 结构校验 | "一个外壳不能被另一个外壳收编"——会把这个外壳收编的**全部**成员逐一点名 |
| 同一个组件同时写 `servedBy` 和 `local: true` | 结构校验 | 明确指出两者语义矛盾（"local 是本机调试，servedBy 是代码已经打进另一个外壳镜像"） |
| 同一个 `(组件ID, 精确版本)` 既独立声明又被某个 `servedBy` 收编 | 结构校验 | 就是通用的"重复声明"报错，不是 `servedBy` 专属逻辑 |
| `servedBy` 指向一个 `brickkit.yaml` 里根本不存在的组件 ID | 生成阶段（比结构校验晚，依赖图解析完才报） | 指出目标不存在，建议检查有没有写错 ID/版本号 |
| `servedBy` 指向一个存在但被 `enabled: false` 或没启动的外壳 | 生成阶段 | 指出"代码没有地方可以运行"，建议确认外壳没被关掉 |
| `local: true` 配上 `deploy.target: k8s` | 生成阶段 | 集群里的 Pod 访问不到开发者本机上的进程，报错会点名组件+两条可执行建议 |
| `deploy.target: k8s` 下 `expose: true` 没配 `hostname` | 生成阶段 | K8s 通过 Ingress + 域名路由对外暴露，不像 Docker 那样映射宿主机端口，必须配 `hostname` 而不是 `exposePort` |

**遇到这类报错不用怀疑是不是环境问题**——以上全部是 `brickkit.yaml` 声明层面的静态/生成期校验，跟 Docker/K8s/本地哪种环境无关，报错文案都精确点名了具体组件和具体原因，照着改就行。

⚠️ **外壳态与全拆态不能同时对着真实基础设施跑**——同一时刻只能有一个在跑（会撞端口、撞 NATS 广播、撞数据库状态），完整推理见《BrickEnterprise 设计书.md》§13.9。

---

## 六、出问题时先看这里

| 症状 | 多半是什么 | 怎么确认 |
|---|---|---|
| `required variable XXX is missing a value` | **compose 没读到 `.env`** | 加 `--env-file .env`（§2.1） |
| `port is already allocated` | 宿主机端口被占 | §1.2 那条命令 |
| `be-casdoor` 反复重启，日志里 `password authentication failed` | `.env` 里的 `POSTGRES_PASSWORD` 和 PG 里的对不上（比如改了 `.env` 但没重建 `pg_data` 卷） | `docker logs be-casdoor \| tail -20` |
| `be-casdoor` 反复重启，日志里 `no schema has been selected to create in` | `casdoor` schema 没建出来 | §3.2 手动补 |
| 容器全 `healthy`，但网关 404 | Traefik 的路由配置没生成（阶段三之后才有组件路由） | `curl http://localhost:28080/api/rawdata` |
| `infra-iam-casdoor` 是 `healthy`，但日志里 `登录 Casdoor 管理 API 失败` | `.env` 的 `CASDOOR_ADMIN_PASSWORD` 跟 Casdoor 真实 admin 密码对不上（§4.4）——不会崩容器，但自举/`BatchGetUsers` 会一直不可用 | 确认 Casdoor 当前 admin 密码，改 `.env` 对齐后重启这一个容器 |
| `frontend/standard` 登录页打不开/OIDC 报错 | `casdoorClientId` 还是空的，或 `iamIssuerUrl` 还是本地占位值 `localhost:8000` | §4.5/4.6 |
| 某个容器 `unhealthy` 但日志说自己起来了 | 健康检查命令在那个镜像里跑不通 | `docker inspect -f '{{json .State.Health}}' <容器> \| head -c 500` |
| `make check` 报「端口被占：xxxx 被 宿主机某进程（权限不足看不到名字…）」 | **正常降级，不是脚本坏了。** 占用端口的进程不是当前用户的（常见于别人用 root/sudo 起的容器或服务），非 root 用户本来就看不到别的用户进程的名字，这是 `ss` 的权限模型，不报错只是那一列查不到 | 按提示 `sudo ss -ltnp \| grep :<端口>` 自己查，或 `sudo lsof -i :<端口>` |
| `make check` 全部 `○ 缺失` 或部分 `✓`，退出码却是 0 | **这是设计如此。** 只有「不对」（镜像/端口/健康不符、端口被占）才算 `✗`，「还没启动」不算——第一次装机前本来就该是这样 | 无需处理，跑 §2.1 第 ③ 步启动 |
| `make check` 失败，但看到的是 `make: *** [Makefile:19: check] Error 2` 而不是 `Error 1` | **正常。** GNU Make 自己的错误码约定是「recipe 出错就报 2」，不透传脚本内部的 `exit 1`。两者都是非零，判断「成功/失败」不受影响 | 无需处理 |
| `make <替换件>-up` 报「与 xxx 属于同一互斥组…」 | **正常，这是设计如此。** 同一能力（存储/身份/事件总线/网关）只能装一个实现，不会帮你自动停旧的 | 按提示 `make <旧实现>-down` 关掉，再重新 `make <替换件>-up` |
| `container be-nats is unhealthy`，日志是 nats-server 的用法说明（`flag provided but not defined`） | **配置文件问题，不是你的环境问题。** 说明用到的镜像版本变了、`command` 里混进了配置文件才认的参数 | 反馈给我们；临时处理：`docker logs be-nats` 找到具体是哪个 flag，对照 `docker run --rm nats:<版本> --help` 确认 |
| `make up` 卡住不动、最后超时 | 某个容器的健康检查一直过不了（`--wait` 会等到 180 秒） | 开一个新终端 `docker inspect -f '{{json .State.Health}}' <容器>` 看最近几次检查的输出 |
| `be-otel` / `be-loki` / `be-tempo` 反复重启或 `unhealthy`，日志里 `exec: "/bin/sh": stat /bin/sh: no such file or directory` | 正常现象的另一种表现（如果你手动改过 compose 又把 healthcheck 加回去了）：这三个镜像没有 shell，任何 `CMD-SHELL` 形态的健康检查都会这样失败 | 不要给这三个 service 加 healthcheck；改用上面 §2.3 的宿主机侧 curl 探活 |
| `curl http://localhost:3100/ready` 返回 503，`"Ingester not ready"` | Loki 单体模式的正常启动延迟（约 15 秒），不是故障 | 等 15-20 秒后重新 curl |

**卡住了就停下来反馈，不要绕过去。** 尤其不要为了「先跑起来」去改端口、去掉健康检查、或者用 `--project-directory` 之类的参数——那些改动会在装组件时以完全无关的报错形式回来找你。

---

## 七、几个你会遇到但不用理解的词

| 词 | 一句话 |
|---|---|
| 带外容器 | 官方镜像直接跑的东西（PG / NATS / Traefik / Casdoor / RustFS）。它们**不在** `brickkit.yaml` 里 |
| 组件 | 我们写的业务砖，在 `brickkit.yaml` 里。当前 14 个 |
| 外壳 | 把多个组件合并成一个进程来省资源。阶段四才有 |
| schema | 一个组件在数据库里的独立地盘。**严禁跨 schema 查询**，这是权限墙 |
| `be-net` | 所有容器共用的 Docker 网络。缺了它容器之间互相看不见 |
