# 0-10 两个 PostgreSQL 实例

## 1. 结论

**通过**。BrickKit 没有“资源绑定”，组件经自己的配置项连数据库；所以“组件分在两个实例”就是配置：共享值写在 `config/vars.yaml`，某个组件在自己的配置文件里写字面量覆盖（这里 west 把 `PG_PORT` 改成实例 B 的 25432）。三种布局下每个组件都连到了自己的实例、用自己的角色，迁移建的 schema 落在对的实例上；外壳里两个成员各连各的实例，互不混用。带特殊字符的密码在三条注入路径上都原样送达。没有发现 BrickKit 的问题。

## 2. 测了什么、为什么

计划第 0 步：“两个 PostgreSQL 实例”，对应套件 E 的 E5（组件分在两个实例）、E2 的“同一外壳里的成员不互相误用连接”，以及协议 14“多个组件可以共用实例或数据库，也可以分开”。这里验证部署层：配置怎样把组件指到不同实例；单跑、外壳、本机外壳三种形态下连接与迁移的去向；密钥（`${VAR}`）在不同注入路径上是否一致。跨实例的业务协作（契约与事件）要等 SDK，在套件 E 里测。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| BrickKit | CLI v1.7.2；Docker 29.7.1 |
| 实例 A | `make up` 的 `be-postgres`（PostgreSQL 16.15，宿主机 5432）；实验里建库 `r010`、角色 `r010_east`，结束后删掉 |
| 实例 B | 另起的 `postgres:16-alpine`（16.15，宿主机 25432）；库 `r010`、角色 `r010_west`；结束后移除 |
| 区分实例 | 两个库里各有一张 `r010_meta.instance`，值分别是 `A`、`B` |
| 组件 | `demo/east`、`demo/west`：Go，用 pgx 真正连库；`/api/db` 报出连到的实例、库、角色与自己 schema 里的行数；迁移以自己的角色建 schema 与表；都写了 `local.migrationCommand`。外壳 `demo/dbshell` 承载两者 |
| 密钥 | `PG_PASSWORD` 声明 `secret: true`，配置写 `${R010_EAST_PG_PASSWORD}`、`${R010_WEST_PG_PASSWORD}`，值在 `.env`；west 的密码含 `$`、双引号、反斜杠与花括号，`.env` 里用单引号包住 |

## 4. 怎样跑

`r010-setup.sh` 建实例 B、两个库与角色、项目。`run010.sh`：`add --local` 后填配置（east 只写用户与密码；west 另把 `PG_PORT` 覆盖成 25432），`build`；然后依次：east、west 单独运行（外壳 `mode: disable`）；两者进外壳；外壳 `mode: local`。每种布局之前删掉两个实例里的 `east`、`west` schema，之后查 `/api/db` 与两个实例里的 schema。

## 5. 结果

| 步 | 结果 |
| --- | --- |
| `add --local --yes` | 必填键里与 `vars.yaml` 同名的（`PG_HOST`、`PG_PORT`、`PG_DATABASE`）自动写成 `$var:`，只剩 `PG_USER`、`PG_PASSWORD` 要填 |
| 单独运行 | 生成的 compose：east `PG_PORT=5432`、west `PG_PORT=25432`；密码在 0600 的 env 文件里，仍是 `${…}` 引用，由 compose 启动时展开。迁移日志：east “ready on instance A as r010_east”，west “ready on instance B as r010_west”；`/api/db` 同样；两个实例里各只有自己的 schema |
| 进外壳 | 同上：一个外壳进程里，east 连 A、west 连 B；`pg_stat_activity` 里 A 只有 `r010_east`、B 只有 `r010_west` 的连接；迁移仍各自在对的实例 |
| 外壳是本机进程 | 两个成员从源码迁移（`go run -mod=vendor ./cmd/server migrate`），地址改写成 `localhost:5432`、`localhost:25432`；`/api/db` 与 schema 同上 |
| 特殊字符的密码 | 三条路径都认证成功（compose 从 `.env` 展开；BrickKit 展开后编码进外壳 JSON；本机进程的环境）。密码错一个字符认证就会失败，所以三条路径拿到的是同一个值 |

## 6. 观察与异常

- **分实例完全靠配置**：BrickKit 不知道“这个组件用哪个实例”，也不需要知道；覆盖写在组件自己的配置文件里，团队审查时一眼可见。换环境时实例地址写在部署文件的 `vars:`。
- **外壳成员各用各的连接池**：池由成员的模块入口按自己的配置表建，外壳只转交配置；这正是组件实现约定“一切经运行时、配置只经运行时”的要求，SDK 要保持这一点（运行时为每个成员建自己的池，不按进程共享）。
- 单独运行时，`secret: true` 的值进 env 文件但仍是引用，真实值只在 compose 启动时出现；外壳时 BrickKit 在生成阶段展开，值写进 0600 的 env 文件（`$` 写成 `$$`）。两种做法拿到的值一致。
- 我用来打印“外壳 JSON 里密码的形状”的那行脚本没有匹配到（输出为空），不影响结论：认证成功本身证明了值正确。

## 7. 影响

- **套件 E 的 E5–E7**：分实例、分库、审计库独立都是配置层面的事，不需要 BrickKit 的新能力；实验项目用部署文件的 `vars:` 与组件配置覆盖来切换。
- **第 2 步 SDK**：每个成员一个连接池，按成员自己的配置建；外壳不共享池（协议 14 的“外壳中的成员各用自己的角色”）。
- 不需要改设计。

## 8. 原始数据

`dev/rebuild/experiment-data/0-10/run1.txt`（含 `run010.sh` 与生成脚本 `r010-setup.sh`；里面的两个密码只用于这次实验，角色与实例已删除）
