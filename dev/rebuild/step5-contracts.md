# 实验第 5 步的契约

> 2026-10-19 起已发布，契约本身以各契约包为准，这里只记下它们在哪、为什么这样定。依据：D76（安全记录以规范 JSON 字节传输，protobuf 只作信封）；安全 03、09a；协议 03、14；协议第 08 章；底层选择（系统面 gRPC + protobuf，用户面 REST + OpenAPI）。

## 在哪

| 契约 | 位置与版本 | 内容 |
| --- | --- | --- |
| 授权（族契约） | `contract-infra-authz` `v3.0.0-alpha.1` | `be.authz.v3`：`ViewService.Verify`、`DefinitionService.Submit`；Go 包 `authzv3`、Python 模块 `be.authz.v3`；README 写授权成员的义务 |
| 审计 | `infra-audit` 的 `contract/`，标签 `contract/v3.0.0-alpha.1` | `be.audit.v3`：`IntakeService.Submit`、`IntakeService.Watermark`；模块 `github.com/brickKit/infra-audit/contract/v3`；README 写审计组件的义务 |
| 身份（族契约） | `contract-infra-iam` `v3.0.0-alpha.1` | 没有系统方法，所以没有 protobuf：签发的凭据（按 P8.1 核验）与事件 `infra.iam.account_status_changed.v1` |
| 安全记录的 JSON Schema | `be-protocol` 3.0.0-alpha.18 的 `schemas/security/` | 从安全 09a 与协议第 08 章的字段表生成（`be-acceptance` 的 `doc-checks/security-schemas.py`），`make gates` 核对 |

## 原则

- **系统面的方法进契约包，用户面的路由不进**：管理员授予、撤销、角色，审计查询，登录与会话，都是用户面 REST，由组件仓库里的 OpenAPI 描述。
- **信封薄，记录用字节**（D76）：线上的记录不带自己的摘要，摘要放在信封里；接收方先按 schema 校验，再核对字节是规范形式、摘要相符。
- **生成的代码提交在仓库里**：buf 1.74.0 在一次性容器里运行。远程插件的版本等于 SDK 锁定的运行时：protobuf-go v1.36.12、grpc-go 插件 v1.6.2、Python protobuf 36.2 与 grpcio 1.84.0。Python 的 `be` 是各契约包共用的命名空间。

## 定下的设计（AI 决定）

| 问题 | 决定 | 为什么 |
| --- | --- | --- |
| 审计的契约放哪 | `infra-audit` 仓库的 `contract/` 子目录，单独的模块与标签 | 被调方发布契约；不为一个小包另建仓库 |
| JSON Schema 放哪 | `be-protocol`，不放各契约包 | 安全记录是全部组件与成员共用的协议内容，SDK 已按精确版本引用 `be-protocol` |
| 核验回答里成员实例放哪 | 回答的 `instance` 字段（安全 09a） | 只答“未变”的回答不带视图；从备份另建的环境内容相同、摘要也相同 |
| 恢复代次怎样传 | 信封里的 `RevisionRef` 消息，不用字节 | 它是调用本身的字段，不是安全记录 |
| 授权组件从哪里拿到注册表 | 部署时作为授权组件的配置提供，由装配生成，不读项目仓库 | 提交的核对要按注册表判断属主 |
| SDK 何时提交定义、失败怎样 | 启动时提交，被接受之前不就绪；同一版本、同一集合重复提交是幂等的；版本相同而集合不同，整次拒绝（`DEFINITION_VERSION_CONFLICT`） | 改了定义就要升版本，与“镜像标签就是版本”一致 |
| 视图分片按什么分 | 第 5 步一个组件一个分片，第 8 步按负载再定 | 安全 09a 把分片方式列为“在代表部署实验中测量” |
| 审计记录不合格怎样回答 | 单独的回执状态 `INVALID`；来源按 `conflict` 处理，停止重发并告警；不认识的状态也按 `conflict` | 不让一条坏记录挡住整批，也不把它当成已收到 |
| 回执什么时候给 | 写入同步提交之后 | 来源凭回执删除本地行 |
| 身份事件的分区 | 流 `infra.iam`，1 个分区 | 账号状态变化很少 |

## 定稿时发现并修好的

- **组件 ID 的类型**：`owner_component` 与 `authority` 原写作 `Key`，可组件 ID（`infra/authz`、`test/probe-go`）带 `/` 与 `-`，不符合 `Key` 的写法。安全 09a 加了 `ComponentId`。
- **审计转运的字节**：两个 SDK 转运时从各列重新拼出记录，字节与算摘要时的不同。改为写入时存下规范字节、转运原样发送（协议 alpha.17 的 P8.20、P8.21，迁移 0009）；SDK 在 T5.3 跟上。
- **定义的提交**：安全 09a 原来没有定义集合的记录，也没有提交被拒的原因。补了 `be.security.definition_set` 与三个原因：`DEFINITION_OWNER_MISMATCH`、`DEFINITION_INVALID`、`DEFINITION_VERSION_CONFLICT`。
- **账号状态**：原来是行内写法，生成不了 schema，改写成字段表（`be.security.account_status`）。
