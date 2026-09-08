# 组件设计计划

一个组件一份，文件名 = 仓库名（`mdm-customer.md`、`erp-sales.md`…）。

## 什么时候写

**该组件开工之前。** 没有它就开工，等于把设计决策直接写进代码——半年后没人知道为什么 `crm-customer` 不直接查 `mdm-customer` 的表。

具体时机：每个阶段的计划文件写完之后、第一个任务开始之前，把该阶段涉及的组件设计计划一次写齐。

## 它和组件仓库里那三份的关系

一个组件一共四份文档，**缺一不可**（总纲 §4 SOP-D）：

| # | 文件 | 在哪 | 给谁看 |
|---|---|---|---|
| 1 | `docs/design/<仓库名>.md` | **这里**（装配仓库） | 做设计决策的人。**跨组件对照着看**——`erp-sales` 为什么不直接查 `mdm-customer` 的表，只有把两份摆在一起才讲得清。它跟着装配仓库走，组件仓库被 Fork 出去也不会带走它 |
| 2 | `README.md` | 组件仓库根 | 「要不要装它、怎么装」的人。固定七节 |
| 3 | `docs/手册.md` | 组件仓库 | 「已经装了、要用它 / 要改它」的人。固定六节 |
| 4 | `AGENTS.md` + `CLAUDE.md` | 组件仓库根 | **AI 助手**。固定六节，判据与禁令前置、每条带症状 |

第 2、3、4 份必须在组件仓库里，因为组件是独立交付物：客户拿到 `erp-sales-acme` 这个 Fork 目录时，得能只靠这个目录跑起来。

## 怎么改

实现过程中发现设计不对，**先改这份，再改代码**。顺序反了，这份文档一周内就会失真，然后所有人都不再看它。

改完在 commit message 里写清**为什么改**——是设计错了，还是实现发现了设计时不知道的约束。

## 门禁

`make docs-check REPO=<仓库名>` 做机械检查：四份都在、章节齐全、`AGENTS.md` 里无「见上文」类引用、全文无 `TBD` / `TODO` / `待补`。内容质量靠 review。

它进每个组件的 `make all`，与 `contract-check`、`import-scan` 同级。

## 索引

| 组件 | 阶段 | 设计计划 | 状态 |
|---|---|---|---|
| `mdm-customer` | 一 | [mdm-customer.md](./mdm-customer.md) | ✅ 已建成（`v1.0.0`，九门禁全绿） |
| `mdm-product` | 二 | [mdm-product.md](./mdm-product.md) | 📋 已写，未开工 |
| `erp-inventory` | 二 | [erp-inventory.md](./erp-inventory.md) | 📋 已写，未开工 |
| `erp-finance` | 二 | [erp-finance.md](./erp-finance.md) | 📋 已写，未开工 |
| `erp-sales` | 二 | [erp-sales.md](./erp-sales.md) | 📋 已写，未开工 |
| `infra-authz` | 三 | [infra-authz.md](./infra-authz.md) | ✅ 已写（规范源是设计书第 14 章） |
| `infra-iam-casdoor` | 三 | [infra-iam-casdoor.md](./infra-iam-casdoor.md) | 📋 已写，未开工 |

> 随开发进度逐条添加。**不要预先把 61 行都列出来**——那会让「还没写」和「写了但空着」混成一团。
>
> 阶段三还有 7 份待写：`infra-workflow`、`infra-notification`、`integration-im-dingtalk`、`infra-print`、
> `infra-bff-mobile`、`frontend-standard`、`crm-opportunity`（清单与顺序见 [`03-阶段三`](../plans/03-阶段三-业务闭环.md)）。

## 另外两类不是逐组件的文档

| 文档 | 是什么 |
|---|---|
| [`_可替换性地图.md`](./_可替换性地图.md) | **跨组件**的参考——哪些组件的哪部分能换、换了牵连谁、怎么换。单个组件的设计计划 §8 只记了它自己的 Fork 点，这份把**已建成的几个组件**的 Fork 点画在依赖图上，回答"这个 Fork 点会不会牵连到依赖它的组件"——单份设计计划回答不了，因为它只看得到自己。随每个新组件设计计划写完同步补一行 |
| `_调研记录/<阶段编号>-<阶段名>.md` | SOP-R 调研的**完整版**（设计计划 §8 是精炼版）。**一个阶段一份，不是一份累加到底**——写法与命名对齐 `docs/plans/` 的阶段编号，理由同 `docs/dev/实测踩坑记录.md` 已经在用的"文档要分文件管理"原则。目前只有 [`02-阶段二.md`](./_调研记录/02-阶段二.md)（`mdm-product`/`erp-inventory`/`erp-finance`/`erp-sales` 开工前查证 ERPNext/Odoo/Tryton/metasfresh 得到的原始发现） |
