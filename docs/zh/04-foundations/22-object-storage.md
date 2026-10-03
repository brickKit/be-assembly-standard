[English](../../en/04-foundations/22-object-storage.md) · [中文](22-object-storage.md)

# 对象存储

文件和大结果放在哪里：S3 API 作为端口；每个组件一个 bucket、一份凭据；每个官方 SDK 的 blob 客户端在线上做什么；预签名的上传和下载；附件以及它的授权和病毒扫描；保留与 Object Lock；大结果按引用交接；冻结数据放在哪。读者是要存文件、要返回 PDF、要给单据加附件，或者被要求支持另一款存储产品的人。

## 范围

- **覆盖：** 配置键；bucket、凭据和策略；bucket 内的键布局；blob 客户端的操作；预签名 URL；附件组件；扫描；生命周期规则和 Object Lock；大结果的 claim check；冷存储在 bucket 里的位置。
- **不覆盖：** 数据生命周期引擎、它的分层、Parquet 格式与清单、`ColdStore` 和 `ColdQuery` 适配器（[09-data-lifecycle.md](09-data-lifecycle.md)）；密钥的下发和轮换（[24-config-and-secrets.md](24-config-and-secrets.md)）；浏览器到对象存储的路由（[18-edge.md](18-edge.md#经边缘访问对象存储)）；对象存储的备份（运维文档，计划中）。

## 选择

- **S3 API 就是端口**（[0106](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)）。RustFS 是默认服务端；MinIO、AWS S3、阿里云 OSS 和其他兼容 S3 的存储靠配置替换。绝不读产品专属的键（`MINIO_*`、`RUSTFS_*`）。
- **每个组件一个 bucket、一份凭据**，策略只够得着自己的 bucket：这是"每个组件一个 schema 加一个角色"（[0102](../02-decisions/01-architecture/0102-one-schema-per-component.md)）在对象存储上的形式。be-ops 在 `make db-init` 旁边生成 `make storage-init`。
- **每个官方 SDK 都有 blob 客户端**，操作和规则相同（协议 P17），底下是各语言的 S3 库（Go 用 `aws-sdk-go-v2`，Python 用 `aioboto3`）。
- **文件绝不经过组件的请求体或响应体。** 浏览器用预签名 URL 上传和下载，有效期最多 5 分钟；bucket 永不公开可读。
- **`infra/attachment` 管附件**：元数据、经父记录授权、上传进隔离区、扫描、放行。
- **扫描是适配器**：经 `SCAN_URL` 用 ClamAV，或者不扫。默认生产开、开发关。
- **保留靠生命周期规则**；法定档案用合规模式的 Object Lock；可能要被擦除的数据绝不上锁。
- **大结果按引用交接**（claim check）：gRPC 回答或事件里放对象键和校验和，绝不放字节。

**状态**：已就位：共享键 `S3_URL` 和 RustFS 容器（MinIO 是互斥的 profile）；没有组件用对象存储，组件手里没有存储凭据，infra/print 把 PDF 字节放在 gRPC 响应里返回，超过 4 MiB 的消息上限就失败。已定（随 3.0.0 统一升级和 SDK v0.6.0 落地）：配置键、每组件一个 bucket 加一份凭据、`make storage-init`、blob 客户端、预签名规则、`blob` 套件、print 改为渲染到对象。以后：`infra/attachment` 和扫描（已登记，端口 8204，schema `infra_attachment`，未建），等第一张需要附件的单据出现时再建；冷存储的 `s3-parquet` 适配器跟随数据生命周期的分期（[09](09-data-lifecycle.md)）。

## 端口契约

### 配置键

| 键 | 共享 | 默认 | 含义 |
|---|---|---|---|
| `S3_URL` | 是，`$var:S3_URL` | — | 项目网络内对象存储的 API 地址 |
| `S3_PUBLIC_URL` | 是 | `S3_URL` | 浏览器用的地址；预签名 URL 按它签名 |
| `S3_REGION` | 是 | `us-east-1` | 签名用的 region |
| `S3_FORCE_PATH_STYLE` | 是 | `false` | RustFS 和 MinIO 用 `true` |
| `S3_BUCKET` | 否 | —（必填；部署时写入 registry 里的 bucket 名） | 本组件的 bucket |
| `S3_ACCESS_KEY_ID_FILE`、`S3_SECRET_ACCESS_KEY_FILE` | 否，密钥，以文件交付（`mount: file`，值写 `${…}`） | — | 本组件自己的凭据，文件变了就成对重读（[24](24-config-and-secrets.md#端口契约)） |
| `SCAN_URL` | 是（只有附件组件用） | 缺省 = 不扫描 | 扫描器，`clamd://<host>:3310` |

组件的 `configSchema` 声明了 `S3_BUCKET`，就表示它用对象存储；这同时打开组件协议套件的 `blob` profile。这里除 `SCAN_URL` 之外的键都是协议键（`be-protocol` 的 `schemas/config-keys.yaml`，P17）。

### bucket、凭据、策略

- `registry/schemas.tsv` 加一列只增的 `bucket`。默认名就是 registry ID（`erp-finance`、`infra-attachment`），因为 S3 的名字不允许下划线。bucket 名全局唯一的地方（AWS S3、OSS），部署方在组件的 `S3_BUCKET` 里写一个带前缀的名字。
- 策略只允许对自己的 bucket 及其对象做 `s3:GetObject`、`s3:PutObject`、`s3:DeleteObject`、`s3:ListBucket`、`s3:AbortMultipartUpload`、`s3:ListMultipartUploadParts`，开了 Object Lock 的再加 `s3:PutObjectRetention` 和 `s3:PutObjectLegalHold`。别的一概没有：不能建 bucket，不能改策略，碰不到别的 bucket。
- `make storage-init` 是幂等的：建每个 bucket，屏蔽公开访问，建组件的用户和 access key，挂上策略，装好下面的生命周期规则；只对生命周期声明需要它的组件开 Object Lock（以及它所要求的版本控制）。生成的凭据放到 `config/` 以密钥形式引用的地方，绝不进受版本管理的文件。
- 外壳里每个成员保留自己的凭据和自己的客户端（[27-shells.md](27-shells.md)）。

### 键布局

| 前缀 | 谁写 | 生命周期规则 | 说明 |
|---|---|---|---|
| `quarantine/<id>` | 附件上传 | 24 小时后过期 | 永远不能下载 |
| `clean/<id>` | 附件组件，扫描通过后 | 无；随附件删除 | |
| `tmp/` | 任何组件：渲染出的文件、claim check 的结果 | 24 小时后过期 | |
| `exports/<job>/` | 生命周期引擎的异步导出 | 导出到期时删除 | |
| `cold/<table>/v<n>/unit=<YYYY-MM>/tenant=<t>/part-NNNN.parquet`、`cold/<table>/_manifests/<unit>.json` | 生命周期引擎 | 无；由引擎决定 | 冷数据放在组件自己的 bucket 里；格式和清单见 [09](09-data-lifecycle.md#冷层格式) |
| `_erasures/` | 生命周期引擎 | 无；只追加 | 按时间点恢复之后重放擦除 |

每个 bucket 还会在 24 小时后中止未完成的分段上传。对象键里绝不放个人信息或文件名：键会出现在日志和 URL 里；文件名放在元数据和 `Content-Disposition` 里。

### blob 客户端

每个官方 SDK 的操作相同；每次调用都带上调用方剩余的截止时间（[16](16-deadlines-and-retries.md)）。

| 操作 | S3 请求 | 规则 |
|---|---|---|
| put | `PutObject`，超过 SDK 的分段大小走分段上传 | 一律设置 `Content-Type` |
| get | `GetObject`，可带 `Range` | 流式读；绝不把整个对象读进内存 |
| head | `HeadObject` | 大小、类型、校验和 |
| delete | `DeleteObject` | 幂等 |
| list | 按前缀 `ListObjectsV2` | 给生命周期引擎和 reconciler 用 |
| presign put | 预签名的 `PutObject` | 见下 |
| presign get | 预签名的 `GetObject` | 见下 |

错误：`NoSuchKey` → `NOT_FOUND`；`AccessDenied` → `INTERNAL`（是配置错误，带 bucket 记日志，绝不给用户看）；`SlowDown` 和 5xx → 在截止时间内退避重试，之后 `UNAVAILABLE`。

### 预签名 URL

- 只在调用方的授权检查过之后才签发；有效期最多 300 s；按 `S3_PUBLIC_URL` 签名。完整的 URL 绝不进日志：签名部分被脱敏。
- **上传**：预签名的 `PUT` 把 `Content-Type` 和客户端声明的确切 `Content-Length` 签进去，所以存储会拒绝任何别的大小。S3 没法给预签名 `PUT` 设一个大小范围；浏览器表单上传改用预签名 `POST`，它的 policy 里带 `content-length-range`。
- **下载**：预签名的 `GET` 带 `response-content-disposition: attachment; filename*=UTF-8''<编码后的文件名>` 和 `response-content-type`；只有白名单里的安全类型（PDF、位图）才用 `inline`。
- 浏览器经边缘上一个独立的主机名到达对象存储（[18](18-edge.md#经边缘访问对象存储)）。

### 附件（`infra/attachment`，以后）

元数据，每个文件一行：`id`（UUIDv7）、`owner_component`、`resource_type`、`resource_id`（文本）、`filename`、`content_type`、`size_bytes`、`sha256`、`state`（`PENDING_UPLOAD`、`SCANNING`、`READY`、`REJECTED`、`DELETED`）、`scan_result`、`legal_hold`、`created_by`、`created_at`。

| 端点 | 做什么 |
|---|---|
| `POST /infra/attachment/uploads` `{resource_type, resource_id, filename, content_type, size, sha256, idempotency_key}` | 经属主的 `POST {prefix}/_authz/check`，用属主为"挂附件"声明的键检查父记录；回答 `{attachment_id, upload: {method, url, headers, expires_at}}`，上传进 `quarantine/` |
| `POST /infra/attachment/attachments/{id}:complete` | head 一下对象，核对大小和校验和，开始扫描 |
| `GET /infra/attachment/attachments?resource_type=&resource_id=` | 检查一次父记录，列出它的附件 |
| `GET /infra/attachment/attachments/{id}/download` | `{url, expires_at}`，只在 `READY` 时给 |
| `DELETE /infra/attachment/attachments/{id}` | 标为 `DELETED`；没有法律保全时对象随之删除 |

- 父记录不可见时，每个端点都答 404（[15](15-user-api-and-errors.md#访问相关的状态码)）；不提供跨父记录的"我能看到的全部附件"（[20](20-authorization-provider.md#端口契约)）。
- 事件 `infra.attachment.attachment.ready.v1`、`.rejected.v1`、`.deleted.v1`，聚合类型 `infra.attachment.attachment`。
- 附件组件带着用户的 token、经用户面去调每个属主的资源契约，并把这些属主声明为可选依赖，与所有做聚合的组件一样（[02-backend.md](../01-conventions/02-backend.md#调用其他组件)）。

### 扫描

- `SCAN_URL` 按 scheme 选适配器：`clamd://` 把对象流式送给 ClamAV（`INSTREAM`）；缺省就是 `none`：文件直接 `READY`，`scan_result: SKIPPED`，组件在启动时告警一次。
- 干净：把 `quarantine/<id>` 复制到 `clean/<id>`，删掉原件，置 `READY`，发事件。有毒、超出扫描器能处理的大小、或者重试后扫描器仍然出错：`REJECTED`，绝不在没扫过的情况下放行。
- ClamAV 是基础设施（官方镜像加配置，[0106](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)），GPL 许可，但作为独立进程使用。

### 保留与 Object Lock

- 生命周期规则处理上面那些短命的前缀。
- **合规模式的 Object Lock**，每个对象各带一个保留截止日期，绝不设成 bucket 的默认值：用于冻结的 ledger 单元和电子会计档案，它们的表不含个人信息。法律保全在开了 Object Lock 的地方用存储自己的对象级 legal hold，别处用 `legal_hold` 标记。
- **可能被擦除的绝不上锁**：可擦除的表冻结时不带保留期，所以它们的对象可以重写（[09](09-data-lifecycle.md#擦除)）。再加上"ledger 表不含个人信息"，"不可篡改"和"可以擦除"永远落在不同的对象上。
- 静态加密是存储自己的设置，不属于本契约。

### 大结果

- **渲染**：infra/print 新增 `RenderToObject`（契约里的加法）：文件写进 print 的 bucket 的 `tmp/` 下，回答里带附件 ID 或者预签名 `GET`。原有的 rpc 保留，并把它的 4 MiB 上限写进契约。
- **超过 64 KiB 的事件**（[13-event-contracts.md](13-event-contracts.md)）带生产者 bucket 里一个对象的 `{key, sha256, size}`。消费者从不持有生产者的凭据：它经生产者为此声明的一个 rpc 拿到一个短期的预签名 URL。

## 备选方案

文件怎么存：

| | S3 API，每组件一个 bucket 加一份凭据（选用） | 文件存在 PostgreSQL 里（`bytea`、large object） | 共享一个 bucket，每组件一个前缀 | 经组件中转上传 | 共享文件系统（NFS、卷） |
|---|---|---|---|---|---|
| 隔离 | 每个 bucket 一份策略 | 每组件一个 schema | 一把钥匙读全部 | 视情况 | 无 |
| 大文件 | 直传，分段 | 撑大备份和复制 | 直传 | 穿过进程 | 直传 |
| 可移植 | 每朵云、每种本地存储 | 数据库 | 每种存储 | — | 按主机 |
| 保留、WORM | 生命周期规则、Object Lock | 手工 | 按前缀的规则 | — | 无 |

用哪个服务端（都在同一个端口后面）：

| 服务端 | 许可证 | 适合 | 留意 |
|---|---|---|---|
| RustFS（默认） | Apache-2.0 | 单机、小集群 | 年轻；IAM 策略和 Object Lock 待实测 |
| MinIO | AGPL-3.0 | 行为已知，IAM 成熟 | 社区版自 2025 年起被削减；许可证条款 |
| Ceph RGW | LGPL | 已经在跑 Ceph 的客户 | 单机太重 |
| SeaweedFS | Apache-2.0 | 海量小文件 | S3 覆盖度待实测 |
| AWS S3、阿里云 OSS、腾讯云 COS | 托管 | 已在该云上的客户 | bucket 名全局唯一；OSS 用它的 S3 兼容模式 |

## 为什么选它

- **处处同一种隔离模型**：一个组件在数据库里只读写自己的 schema，在对象存储里只读写自己的 bucket，用的都是自己的凭据。
- **大文件从不穿过组件**，所以内存、1 MiB 的请求体上限、4 MiB 的 gRPC 上限都挡不了路，外壳里的成员也不会被某个成员的上传拖慢。
- **S3 API 是每种存储都会说的话**，所以客户现有的存储只是一个配置值。
- **授权留在拥有这个文件的记录那里**：附件的可见性与它的父记录一样，由父记录的属主决定。

## 为什么不选其他

- **`bytea` 或 large object**：每个文件都进备份、复制和按时间点恢复；数据库是存字节最贵的地方。
- **共享 bucket 加前缀**：漏一把凭据就能读到每个组件的文件；按前缀的策略做得到，但没有任何东西按组件去检查它。
- **经组件中转上传**：每次上传都在一个同时要服务请求的进程里占着连接和内存，还要一个别的路由都不需要的请求体上限。
- **共享文件系统**：没有预签名访问，没有保留规则，在 Kubernetes 上没有存储类就用不了。
- **产品 SDK**（MinIO 的、OSS 的）：把代码绑死在一款产品上，违反 0106。

## 什么时候换

- **客户自己的基础设施**：用他们的存储，改配置即可。
- **RustFS 在某项实测要求上不达标**（策略、Object Lock、分段上传）：换成 MinIO 或者另一个通过 `blob` 套件的服务端。
- **强制要求用 ClamAV 以外的防病毒产品**：在 `SCAN_URL` 后面加一个新的扫描器适配器。
- **跨组件读文件变得常见**：重审 claim check，而不是凭据规则。

## 怎么换

1. 起好新的存储；在 `config/vars.yaml` 里设置 `S3_URL`、`S3_PUBLIC_URL`、`S3_REGION`、`S3_FORCE_PATH_STYLE`。
2. 对它跑 `make storage-init`；把新凭据放到 `config/` 引用它们的地方。
3. 逐个 bucket 复制对象（`rclone sync`，或存储自带的镜像工具）。
4. 对新存储跑 `blob` 套件；重启组件。组件代码、契约、版本钉都不变。

扫描器：设置或去掉 `SCAN_URL`，别的都不动。

## 一致性测试

计划中的套件 `tools/be-acceptance/conformance/blob/`，对 RustFS、MinIO、AWS S3 和 OSS 各跑一遍：

- 预签名 `PUT` 拒绝长度不同的请求体；预签名 `POST` 拒绝超出范围的请求体；
- 预签名 `GET` 过期后答 403；`Range` 读取返回正确的字节；分段上传能完成、能中止；
- 一个组件的凭据不能列出、读取或写入另一个组件的 bucket；匿名读被拒绝；
- 生命周期规则让 `quarantine/` 和 `tmp/` 过期；
- 合规模式的 Object Lock 下，在保留截止日期之前删除会失败。

组件协议套件（`tools/be-acceptance/conformance/component/`）的 `blob` profile：预签名上传带长度上限；bucket 不能被匿名读；预签名 URL 最多活 5 分钟。

先写成红的测试：be-sdk-go "超过声明大小的预签名上传被拒"、"预签名下载过期后答 403"、"凭据够不着别的组件的 bucket"；be-ops "storage-init 幂等地建好每个 bucket 和策略"；infra/print "超过 4 MiB 的结果走 `RenderToObject`"；附件组件建成时："扫描之前不能下载"、"父记录不可见答 404"。

## 相关决策

- [0106 基础设施不是组件](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)：S3 API 是端口；存储和扫描器都是基础设施。
- [0102 一个数据库，每个组件一个 schema](../02-decisions/01-architecture/0102-one-schema-per-component.md)：本文把这套隔离模型推广到 bucket。
- [0302 契约只做加法](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)：`RenderToObject` 与原有 rpc 并存。
- [0212 调用者看不见的记录答 404，读和命令都一样](../02-decisions/02-permissions/0212-invisible-records-answer-404.md)：父记录不可见时，它的附件答 404。
- 计划中、尚未编号："每个组件一个 bucket、一份凭据"。

## 已知限制

- **RustFS 的 IAM 策略和 Object Lock 还没实测**；在 `blob` 套件跑通之前，Object Lock 只对跑通了的存储承诺。
- **预签名 URL 谁拿到谁就能用**，直到过期（最多 5 分钟）。
- **浏览器需要一条到对象存储的路**，用它自己的主机名；只在项目网络内可达的存储没法提供预签名 URL。
- **附件多一个新属主**，就要附件组件发一版，把它加成可选依赖。
- **保留只经事件跟随父记录**：父记录销毁后，事件处理之前附件还在。
- **附件和扫描还没建**；在那之前没有组件接收文件。
