[English](../../../en/02-decisions/03-contracts-and-data/0308-tenant-is-the-deployment.md) · [中文](0308-tenant-is-the-deployment.md)

# 0308 租户就是部署；公司是部署内的法人

**状态**：已决定，随 3.0.0 统一升级落地。

## 决策

- **一个客户，一套部署。** 项目以私有化部署为主，每个客户一套安装。没有多个客户共用一个数据库的多客户 SaaS 模式。
- **一个客户，一个项目仓库 fork。** brickKit 没有多客户的概念：每个客户的 fork 持有自己的 `brickkit.yaml`（它的锁文件，所以版本按客户逐个推进）、`config/`、密钥和部署文件；共用的改动用 Git 从上游仓库合并进来（[07-tenancy.md](../../04-foundations/07-tenancy.md#运营多个租户)）。
- **租户在线上预留，不进表。** token 带 `tenant_id`，`aud` 是本部署的 `TENANT_ID`（[0203](../02-permissions/0203-jwt-carries-identity-only.md)）；契约可以带租户字段。任何表都没有 `tenant_id` 列。
- **一个客户下的多家公司是法人**，是部署内的一个维度，归 `mdm/org` 所有：
  - 每张交易单据都带 `legal_entity_id`；
  - 关于这些单据的事件也带它（`ce-legalentity`）；
  - 单据号按法人和期间划分范围（[0306](0306-uuidv7-own-keys.md)）；
  - 每个法人有自己的日历和本位币（[0307](0307-business-dates-and-legal-entity-calendar.md)、[0301](0301-money-as-strings-lists-by-cursor.md)）；
  - `legal_entity` 是数据范围维度（[0205](../02-permissions/0205-data-scopes-ship-with-the-version.md)），所以跨法人的报表和任何读取一样受范围约束。

## 理由

客户把系统装在自己的机器上，客户之间的隔离就是部署本身，这是最强的隔离。另一方面，集团多公司现在就需要，而且必须在一套安装里共用主数据、用户和角色，这正是法人维度提供的。在 token 和契约里预留租户，以后若要做共享模式就只需加法，而今天不必为每一行、每一条查询付 `tenant_id` 的代价。

## 挡下什么

- 任何组件里的 `tenant_id` 列，或查询里按租户过滤
- 一套部署服务几个互不相干的客户
- 同一集团、共用主数据的各家公司各自一套部署
- 交易单据或其事件缺少法人

## 何时重新讨论

共享的多客户产品成为产品决策时。线上预留的租户字段是起点；表和查询届时需要一次单独规划的改动。

完整分析：[07-tenancy.md，选择](../../04-foundations/07-tenancy.md#选择)。
