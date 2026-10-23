<!-- brickkit:components lang=zh -->
<!-- 由 brickkit 维护（init、add、remove、upgrade、skills update），来自 brickkit.yaml 与各组件的 component.yaml：整份文件会被改写 -->
# 组件

本项目用到的每个组件，版本是 `brickkit.yaml` 钉住的那个。各组件的文档与契约在哪：见 `AGENTS.md` 末尾。

| 组件 | 版本 | 干什么 | 文档 | 主页 |
|---|---|---|---|---|
| mdm/customer | 2.0.1 | Customer names, tax IDs, credit limits, status, contacts and billing details. | BRICKKIT.md +zh | https://github.com/brickKit/mdm-customer |
| infra/authz | 2.0.1 | Permission key catalogue, roles as plain unions, the policy bundle served at /authz/bundle, and login-time claims. | BRICKKIT.md +zh | https://github.com/brickKit/infra-authz |
| infra/notification | 2.0.0 | Takes notification intents from business components and routes them to the installed channel adapters by each user's preferences. | BRICKKIT.md +zh | https://github.com/brickKit/infra-notification |
| infra/workflow | 2.0.1 | A light task inbox; business components register approval and exception tasks, and completion is reported back by event. | BRICKKIT.md +zh | https://github.com/brickKit/infra-workflow |
| mdm/product | 2.0.0 | SKUs, categories, unit-of-measure conversions, batch and serial tracking policies, and standard costs. | BRICKKIT.md +zh | https://github.com/brickKit/mdm-product |
| integration/im-dingtalk | 2.0.0 | The DingTalk member of the IM channel family; sends work notifications for IM dispatch events and publishes the delivery results. | BRICKKIT.md +zh | https://github.com/brickKit/integration-im-dingtalk |
| infra/print | 2.0.0 | A pure rendering service; a template ID plus JSON data becomes a PDF byte stream or a ZPL command stream, with no business logic. | BRICKKIT.md +zh | https://github.com/brickKit/infra-print |
| erp/inventory | 2.0.0 | Stock balances, movements and reservations, with oversell protection; the only writer of physical stock movements. | BRICKKIT.md +zh | https://github.com/brickKit/erp-inventory |
| erp/finance | 2.0.0 | Chart of accounts, general ledger entries, receivable and payable ledgers, period locks and reconciliation. | BRICKKIT.md +zh | https://github.com/brickKit/erp-finance |
| infra/iam-casdoor | 2.0.0 | A thin adapter in front of Casdoor; issues and refreshes application tokens, serves /api/tenant/features and bridges Casdoor webhooks. | BRICKKIT.md +zh | https://github.com/brickKit/infra-iam-casdoor |
| erp/sales | 2.0.0 | Sales quotations and the order lifecycle, pricing, and the compensating orchestration that reserves stock when an order is confirmed. | BRICKKIT.md +zh | https://github.com/brickKit/erp-sales |
| crm/opportunity | 2.0.0 | Opportunity lifecycle, sales funnel and win-forecast data; publishes won, lost and stage-changed events. | BRICKKIT.md +zh | https://github.com/brickKit/crm-opportunity |
| infra/bff-mobile | 2.0.0 | GraphQL backend-for-frontend for the mobile app; a schema cut to the pages, batched loading, no business logic and no database. | BRICKKIT.md +zh | https://github.com/brickKit/infra-bff-mobile |
