[English](configuration.md) · [中文](configuration.zh.md)

# 配置约定

## 键名

配置键即环境变量名：大写，单词间用下划线。组件代码从运行时配置对象读取，不直接读进程环境变量。

以下名字禁用，平台保留并会跳过或拒绝：

- `COMPONENT_ID`、`COMPONENT_VERSION`
- 以 `_ENDPOINT` 结尾的任何名字（平台用这类名字注入依赖地址）

仅属于单个组件的键命名为 `<领域名词>_<含义>`，例如 `DEFAULT_WAREHOUSE_ID`。多个组件共用的键使用下一节的名字，不按组件改名。

## 共享连接键

连接信息是各组件 `configSchema` 中声明的普通配置项，平台不会代为注入。

| 键 | 含义 | 值的来源 | 是否 secret |
|---|---|---|---|
| `PG_HOST` | PostgreSQL 主机 | `$var:PG_HOST` | 否 |
| `PG_PORT` | PostgreSQL 端口 | `$var:PG_PORT` | 否 |
| `PG_DATABASE` | PostgreSQL 数据库名 | `$var:PG_DATABASE` | 否 |
| `PG_USER` | 本组件的登录角色 | 字面量（即其 schema 名） | 否 |
| `PG_PASSWORD` | 该角色的密码 | `${<SCOPE>_<NAME>_DB_PASSWORD}` | 是 |
| `PG_SCHEMA` | 本组件独占的 schema | 字面量，照抄 `registry/schemas.tsv` | 否 |
| `NATS_URL` | 事件总线地址 | `$var:NATS_URL` | 否 |
| `S3_URL` | 对象存储地址（完整 URL） | `$var:S3_URL` | 否 |
| `OTEL_BASE_URL` | 遥测采集器基础地址；留空即关闭导出 | `$var:OTEL_BASE_URL` | 否 |
| `AUTHZ_BUNDLE_URL` | 权限策略包地址 | `$var:AUTHZ_BUNDLE_URL` | 否 |
| `IAM_JWKS_URL` | 身份提供方签名公钥地址 | `$var:IAM_JWKS_URL` | 否 |

## 值写在哪里

- `config/vars.yaml` 存放多个组件共用的值，只写一次。组件用 `$var:NAME` 引用。
- `config/<scope>-<name>.yaml` 存放单个组件自己的值。某个组件需要不同于共享值的值时，在这里写字面量，而不是 `$var:`。
- 部署文件（`deploy.<env>.yaml`）的 `vars:` 段按环境或拓扑覆盖 `config/vars.yaml`，冲突时以它为准。
- 密钥只写成 `${NAME}`，值放在 `.env` 或进程环境变量里，绝不进入受版本控制的文件。

## 数据库角色

每个组件有自己的登录角色。`PG_USER` 取 `registry/schemas.tsv` 中该组件的 schema 名，`PG_PASSWORD` 为 `${<SCOPE>_<NAME>_DB_PASSWORD}`。`PG_SCHEMA` 照抄 `registry/schemas.tsv`，不得自拟。

外壳用自己的角色登录，并对每个成员用 `SET LOCAL ROLE` 切换到该成员的角色。切换始终限定在事务内。

## 依赖地址

强、弱依赖的地址由 brickKit 以 `<ID>_ENDPOINT` 注入，代码通过运行时配置的 endpoint 访问器读取。

权限策略包和身份公钥集刻意不是依赖边：给它们加精确版本锁，会让 authz 或 iam 每次发版都连带全部组件发版。它们的地址是普通配置：`$var:AUTHZ_BUNDLE_URL` 与 `$var:IAM_JWKS_URL`。

外壳服务名为 `<scope>-<name>-<版本，点换成横线>`，因此 `be/go-infra@1.0.0` 的地址主机名是 `be-go-infra-1-0-0`。这些值写在 `config/vars.yaml` 中，拓扑变化时在部署文件的 `vars:` 里覆盖。
