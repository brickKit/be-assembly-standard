[English](../../en/04-foundations/07-tenancy.md) · [中文](07-tenancy.md)

# 多租户

本项目里租户是什么、一个租户的数据怎么和另一个租户隔开、一个客户内部的多家公司怎么表示，以及 token 和事件里带什么，好让将来换模型时仍然只做加法。要加一个标识公司或客户的列、要提议多租户 SaaS、要改 token 的受众校验之前，先读这篇。

## 范围

- **覆盖：** 租户与法人的定义；租户 = 部署；每套部署各自拥有什么；法人列、它的事件和它的数据范围维度；token 里的租户字段，以及校验它们的配置键；为池化模型预留的字段；一套部署内部的吵闹邻居；运营多个租户。
- **不覆盖：** token 验证的全部细节（[21-identity-provider.md](21-identity-provider.md)）；法人的业务时区与会计日历（[05-time-and-calendars.md](05-time-and-calendars.md)）；按法人编号的单据号（[04-identifiers-and-numbering.md](04-identifiers-and-numbering.md)）；数据范围维度怎么求值（[20-authorization-provider.md](20-authorization-provider.md)）；事件头（[13-event-contracts.md](13-event-contracts.md)）；按租户的保留期（[09-data-lifecycle.md](09-data-lifecycle.md)）。

**术语。** **租户**是一个客户，它的数据任何别的客户都永远看不到。**法人**是同一个客户内部的一家公司：法人之间共享主数据，可以互相交易，但每个法人有自己的账、自己的编号和自己的日历。

## 选择

- **一个租户就是一套部署**（"silo"模型）：一个 brickKit 项目实例，独占自己的数据库、NATS、bucket 和身份提供方组织（或者独立的身份提供方）。任何表都没有 `tenant_id` 列。
- **租户内的多家公司是法人，作为行维度。** 每张交易单据表都带 `legal_entity_id TEXT NOT NULL`，仓库也带。主数据（客户、产品）默认在租户的各法人之间共享。
- **法人是主数据，归 mdm/org 所有**。这是本轮新建的组件，排在其余组件升 3.0.0 之前。没有任何列出法人的过渡共享变量。
- **每个交易事件都带法人**，在 payload 里，也在 `ce-legalentity` 头里。消费方收到缺法人的这类事件就送进死信，绝不把它记进一个 `default` 法人。
- **`legal_entity` 是数据范围的一个维度**：角色被授予法人取值，列表查询按它过滤（[20](20-authorization-provider.md)）。
- **token 写明是哪套部署**：`aud` 必须包含 `TENANT_ID`，`iss` 必须等于 `IAM_ISSUER`，并带 `tenant_id` 声明（`org_id` 已弃用）。为一套部署签发的 token，另一套部署会拒收，即使两者用的是同一个身份提供方。
- **池化模型只预留、不建**：事件头 `ce-tenantid` 和 `lifecycle.yaml` 里的 `tenant_key` 都已存在，保持不设。

**状态**：已定；随 3.0.0 统一升级落地（法人列、事件、`TENANT_ID` 与 `IAM_ISSUER` 校验、mdm/org）。今天只有一个租户、一个法人：token 的 `org_id` 是常量，只有 erp/finance 有 `legal_entity_id` 列，事件缺法人时它缺省为 `'default'`，没有任何 SDK 校验 `aud` 或 `iss`。种子数据随这次升级加上第二个法人「本地测试」华南子公司，让这个维度有真实数据可测（[05-data.md](../01-conventions/05-data.md)）。

## 端口契约

### 租户身份

| 项 | 在哪 | 取值 | 规则 |
|---|---|---|---|
| `TENANT_ID` | `config/vars.yaml` 里的共享键，每个有受保护路由的组件以 `$var:TENANT_ID` 引用 | 这套部署的租户标识 | 必填；它就是 `aud` 的期望值 |
| `IAM_ISSUER` | 共享键 | IAM 成员的 issuer URL | 必填；`iss` 的期望值 |
| `aud` 声明 | 每个访问令牌 | 包含 `TENANT_ID` | 不含的令牌答 `401` |
| `tenant_id` 声明 | 每个访问令牌 | 等于 `TENANT_ID` | 记录或审计租户的组件读它；`org_id` 已弃用 |
| `ce-tenantid` | 事件头 | 不设 | 为池化模型预留（[13](13-event-contracts.md)） |
| `tenant_key` | `lifecycle.yaml` | `none` | 预留：池化模型下它写出租户列的名字（[09](09-data-lifecycle.md)） |

### 一套部署各自拥有什么

| 资源 | 每个租户 | 租户之间共享 |
|---|---|---|
| PostgreSQL | 自己的数据库（或服务器）；角色由自己的 `make db-init` 建 | 从不 |
| NATS | 自己的服务器或账号；`BE_*` 流按部署各一套 | 从不 |
| 对象存储 | 自己的 bucket，每个组件一个（[22](22-object-storage.md)） | 从不 |
| 身份 | 自己的 IdP 组织或 IdP；自己的 `IAM_ISSUER` 和签名密钥 | IdP 服务器可以共享；因为有 `aud`，token 仍然不能越界 |
| 边缘 | 自己的主机名和路由 | — |
| 密钥 | 自己的 `.secrets/` 或密钥库 | 从不 |

### 法人

- **列**：`legal_entity_id TEXT NOT NULL`，即该法人在 mdm/org 里的 id，按引用存成文本（[04](04-identifiers-and-numbering.md)）。没有默认值。
- **带这一列的表**：交易单据以及由它们过账出来的一切：销售订单、出入库流水与预留、商机、引用了单据的待办、凭证、应收应付台账。仓库作为归属方也带这一列。
- **不带的表**：主数据默认是整个租户共用的。某个组件需要"这个客户只给 A 公司用"时，自己加一张关联表；主表不变。
- **唯一性与编号**：单据号在法人内唯一，`UNIQUE (legal_entity_id, <编号列>)`，并按法人和期间编号（[04](04-identifiers-and-numbering.md)）。
- **事件**：payload 里有 `legal_entity_id`；运行时把它复制进 `ce-legalentity` 头（[13](13-event-contracts.md)）。交易事件缺了它：消费方把消息送进死信 subject。
- **数据范围**：维度 `legal_entity`。取值在授权提供方里按角色和键授予，随 bundle 下发；组件的列表谓词像其他资源维度一样与它取 AND（[20](20-authorization-provider.md)）。跨法人的汇总（例如信用敞口）按法人分别计算，绝不把调用方看不到的法人加在一起。
- **组件需要的法人属性**（编码、名称、业务时区、会计年度起始月、本位币）来自 mdm/org。组件经 SDK 的快照帮手在本地留一份副本，经 SDK 读日历（[05](05-time-and-calendars.md)）。

### 运营多个租户

- SaaS 运营方给每个租户一套部署。在 Kubernetes 上是每个租户一个 namespace；在 Docker 或 Podman 上是每个租户一个项目目录。
- 一个租户的部署文件，是共用的 `deploy.yaml` 加一个环境文件（`brickkit … -f deploy.<tenant>.yaml`），它只覆盖 `vars:`：`TENANT_ID`、`IAM_ISSUER`、库和总线地址、主机名。
- 升级、备份、恢复都按租户进行。一个租户可以停在旧的组件版本上，另一个先升。

### 租户内部的吵闹邻居

一套部署内部的邻居是组件，不是租户。约束它们的是：每个成员的连接预算 `PG_POOL_MAX`（[03](03-database.md)）；按事务、按角色的超时（[10](10-local-transactions.md)）；流的大小上限（[12](12-event-bus.md)）；出站舱壁（[16](16-deadlines-and-retries.md)）；各 `component.yaml` 里的 `requests`，会变成 Kubernetes 的 requests 和 limits。

## 备选方案

| 模型 | 隔离 | 每个租户的成本 | 吵闹邻居 | 谁在用 |
|---|---|---|---|---|
| 每个租户一套部署（silo，选定） | 最强；按租户升级、备份、恢复 | 一套进程（一组外壳约 1–2 GB 内存） | 租户之间没有 | SAP S/4HANA Cloud（每租户一个系统）、Dynamics 365 Finance and Operations（每个环境一个库）、Odoo Online（每租户一个库）、专属私有云 |
| 一套部署，每租户一个库 | 强 | 迁移跑 N 遍；每个库一个池 | 计算共享 | 部分 SaaS |
| 一套部署，每租户一个 schema | 中 | 组件数 × 租户数个 schema | 共享 | 早期 Rails SaaS |
| 行级 `tenant_id`（池化） | 最弱，只靠代码保证 | 最低 | 没有配额时很严重 | Salesforce（`OrgId`）、NetSuite、多数小微企业 SaaS |
| 租户内的公司列（不是备选，是补充） | — | — | — | Odoo `company_id`、Dynamics `DataAreaId`、SAP `BUKRS`、ERPNext `company` |

## 为什么选它

- **主流 ERP 云就是这样隔离租户的**，也和本产品的主要交付方式一致：每个客户一套私有化部署。
- **不用写代码**：每个组件一个 schema（[0102](../02-decisions/01-architecture/0102-one-schema-per-component.md)）加上"一个 brickKit 项目就是一套部署"，已经给出每套部署一个租户；`-f deploy.<env>.yaml` 已经给出每个租户一个文件。
- **隔离、升级、备份、恢复都按租户进行**，一个租户的负载永远拖不慢另一个。
- **法人现在就加，而不是以后**：集团多公司在范围内，而分区的交易表有了数据再补列，就要回填并重建唯一索引。放进 3.0.0 的新基线里，没有成本。
- **`aud` 和 `iss` 各只是一次比较**，却堵住了租户之间唯一可能串通的路：两套部署信任同一把签名密钥。

## 为什么不选其他

- **一套部署里每租户一个库**：一个进程一个共享池，没法按库拆开；每次迁移都要在一套部署启动时按租户各跑一遍。
- **每租户一个 schema**：本项目已经是每个组件一个 schema；再按租户乘一遍，就是组件数 × 租户数个 schema、迁移和角色。
- **行级 `tenant_id`**：每张表、每个唯一索引、每条查询都要带租户，而不用行级安全（[0206](../02-decisions/02-permissions/0206-no-row-level-security.md)）时只有 SDK 和门禁能保证它。事后再加，就是每个组件一次大版本。

## 什么时候换

- **出现成千上万个小租户的商业模式**，每个都小到付不起自己的一套进程：判据是每个租户的基础设施成本超过它付的钱。只有到那时，池化模型才值得评估。
- **一个客户有很多分布在不同国家的法人**：不是一次"换"；法人已经覆盖了这种情况，每个法人各有时区和币种。

## 怎么换

- **新租户**：一套新部署。复制项目，写这个租户的 `vars:`（`TENANT_ID`、`IAM_ISSUER`、各地址），对它的库跑 `make db-init`，建它的 IdP 组织，`brickkit up`。不改代码，不改版本钉。
- **新法人**：在 mdm/org 里建它，在授权提供方里给角色授予它的取值。部署不变。
- **换成池化模型**：不是改配置。它是每个组件的一次大版本：在 `lifecycle.yaml` 里声明 `tenant_key`；给每张表、每个主键、每个唯一索引加租户列；让 SDK 的 store 给每条语句加上租户谓词，并配一条门禁和一套套件来证明；设置 `ce-tenantid`；从 token 的 `tenant_id` 取租户。今天预留的字段，让那时的线上契约仍然只做加法。

## 一致性测试

- **组件协议套件**（`tools/be-acceptance/conformance/component/`，[02](02-languages-and-component-protocol.md)）：`aud` 不对的令牌得到 `401`；`iss` 不对的令牌得到 `401`；缺法人的交易事件进死信 subject；`scope` profile 包含 `legal_entity` 取值。
- **SDK，先写红测试**：验签时拒收 `aud` 不含 `TENANT_ID` 的令牌，也拒收 `iss` 与 `IAM_ISSUER` 不同的令牌。
- **erp/sales**：新建的订单存了 `legal_entity_id`，它的事件也带着。
- **erp/finance**：缺法人的事件被拒收，绝不记进 `default`；信用敞口受调用方的 `legal_entity` 取值限定。
- **be-acceptance**：交易单据表缺 `legal_entity_id` 时，一条计划中的扫描报错（表清单取自 `lifecycle.yaml`）。
- **种子数据**：两个法人，并且至少有一个角色只限其中一个。

## 相关决策

- [0308 租户就是部署；公司是部署内的法人](../02-decisions/03-contracts-and-data/0308-tenant-is-the-deployment.md)：本文是它的完整分析。
- [0102 一个数据库，每个组件一个 schema](../02-decisions/01-architecture/0102-one-schema-per-component.md)：为什么 schema 不能再按租户分。
- [0206 不用行级安全，不做共享引擎](../02-decisions/02-permissions/0206-no-row-level-security.md)：为什么池化模型只能靠 SDK。
- [0203 token 只承载身份，`sub` 归平台所有](../02-decisions/02-permissions/0203-jwt-carries-identity-only.md)：`aud`、`iss` 和 `tenant_id` 声明。
- [0107 族成员的地址是共享变量里的 `$endpoint:` 引用](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)：`IAM_ISSUER` 和 `TENANT_ID` 是共享变量。
- [0205 数据范围随版本发布](../02-decisions/02-permissions/0205-data-scopes-ship-with-the-version.md)：`legal_entity_id` 是组件为自己的数据范围声明的列之一。
- [0307 业务日期按法人日历算](../02-decisions/03-contracts-and-data/0307-business-dates-and-legal-entity-calendar.md)：法人的时区与会计年度。

## 已知限制

- **没有池化 SaaS。** 每个租户都要一整套进程。
- **主数据在一个租户的各法人之间共享。** 要把某个客户或产品限定给一家公司，得在拥有它的组件里加关联表。
- **公司间交易**（一个法人卖给另一个法人）是 ERP 组件的业务功能，不在本文设计。
- **同一个人跨租户就是几个账号**：每个租户有自己的 IdP 组织和自己的平台 `sub`。
- **mdm/org 里的法人和 IAM 目录里的部门是什么关系**，在 mdm/org 自己的设计里定。
