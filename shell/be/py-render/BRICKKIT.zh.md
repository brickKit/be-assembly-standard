# be/py-render

## 组件定位

把渲染类的 Python 组件放进一个进程里运行，省下每个组件各一份运行时的内存和 CPU。每个成员仍保留自己的端口、schema、角色、迁移和镜像；外壳只负责托管。

计划放进这个外壳的组件是 `registry/ports.tsv` 里的 `py-render` 端口组：infra/print；之后还有 integration/edi。它目前没有编译进任何成员：每个组件迁移到 brickKit v1 时再加入。

- **负责**：一个 Python 进程；用外壳自己的登录角色打开的一个共享 PostgreSQL 连接池和一条 NATS 连接；权限包只加载一次；端口 8402 上它自己的 `/healthz`。
- **不负责**：任何业务逻辑、路由、表或契约（各归各的成员）；成员的迁移（brickKit 在外壳启动前用成员自己的镜像执行）；一次部署托管哪些成员（由项目的部署文件在已编译进的成员中选择）。

## 部署前准备

- PostgreSQL 登录角色 `shell_py_render`，密码放在环境变量 `SHELL_PY_RENDER_PASSWORD` 里（本地在 `.env`）。`make db-init` 创建它，并对 `shell.members` 里的每个成员把该成员的角色授给它（`GRANT <member>_rw TO shell_py_render`），外壳才能用 `SET LOCAL ROLE` 切到成员身份。没有成员时只创建登录角色。
- 启动时 PostgreSQL 和 NATS 可达：即使一个成员都不托管，外壳也会打开这两条连接。
- 镜像用 `brickkit build` 构建：构建时记录编译进去的成员版本，`brickkit up` 会核对。

## 依赖说明

无。外壳自己没有依赖边；每个成员保留自己的依赖，按它单独运行时一样解析。权限包和身份公钥集是配置，不是依赖。

## 配置指南

| 变量 | 含义 |
|---|---|
| `PG_HOST` | PostgreSQL 主机；外壳为全部成员只开一个共享连接池 |
| `PG_PORT` | PostgreSQL 端口 |
| `PG_DATABASE` | PostgreSQL 数据库 |
| `PG_USER` | 外壳自己的登录角色，绝不是某个成员的角色 |
| `PG_PASSWORD` | 该登录角色的密码（secret） |
| `NATS_URL` | 事件总线地址；外壳为全部成员只开一条共享连接 |
| `OTEL_BASE_URL` | 遥测采集器基地址；留空即不导出 |
| `AUTHZ_BUNDLE_URL` | 权限包地址，整个进程只加载一次；必填，缺了外壳拒绝启动 |
| `IAM_JWKS_URL` | 身份提供方签名公钥地址，整个进程只加载一次；必填，缺了外壳拒绝启动 |

这些是外壳自己的键，从外壳进程环境读取。成员的配置从不来自这里：brickKit 通过 `BRICKKIT_SERVED_MEMBERS_CONFIG` 逐个成员传入。

## 契约索引

无。外壳唯一的接口是端口 8402 上的 `/healthz`，只报告进程活着，不检查任何别的东西。每个成员在自己的端口、以自己的服务名提供自己的契约。

## 外壳声明

这个组件是外壳。编译进的成员（与 component.yaml 的 shell.members 保持一致）：暂无。成员逐个加入；每加一个，同时在外壳代码里登记它，并在 `pyproject.toml` 里加上同一版本。
