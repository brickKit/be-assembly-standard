# Component Design Plans

One file per component, filename = repo name (`mdm-customer.md`, `erp-sales.md`, …).

*[中文](../zh/README.md)*

## When to write one

**Before that component's work begins.** Starting without one means design decisions get written straight into code — six months later, nobody knows why `crm-customer` doesn't just query `mdm-customer`'s tables directly.

Concrete timing: once a phase's plan document is written and before its first task starts, write the design plans for every component that phase touches, all at once.

## How it relates to the three documents that live in the component's own repo

A component has four documents total, and **none of the four is optional** (Master Guide §4 SOP-D):

| # | File | Where | Who reads it |
|---|---|---|---|
| 1 | `docs/design/<repo-name>.md` | **Here** (the assembly repo) | Whoever is making a design decision. **Read across components side by side** — why `erp-sales` doesn't query `mdm-customer`'s tables directly only makes sense once both are laid out together. It travels with the assembly repo, not with a Forked component repo |
| 2 | `README.md` | Component repo root | Whoever is deciding "should I install this, and how" — a fixed seven sections |
| 3 | `docs/手册.md` | Component repo | Whoever already has it installed and wants to use/customize it — a fixed six sections |
| 4 | `AGENTS.md` + `CLAUDE.md` | Component repo root | **The AI assistant** — a fixed six sections, judgment criteria and prohibitions up front, each with a symptom |

Documents 2, 3, and 4 must live in the component's own repo, because a component is an independent deliverable — when a customer receives the `erp-sales-acme` Fork directory, it has to be runnable from that directory alone.

## How to change it

If implementation reveals the design was wrong, **change this document first, then the code.** Do it the other way around and this document goes stale within a week — and then nobody reads it anymore.

When you change it, state **why** in the commit message — was the design itself wrong, or did implementation surface a constraint nobody knew about at design time.

## The gate

`make docs-check REPO=<repo-name>` runs a mechanical check: all four documents present, every required section present, no "see above"-style forward references inside `AGENTS.md`, and no `TBD`/`TODO`/"to be filled in" left anywhere. Content quality is a review matter, not something this gate checks.

It's part of every component's `make all`, at the same level as `contract-check` and `import-scan`.

## Index

| Component | Phase | Design plan | Status |
|---|---|---|---|
| `mdm-customer` | 1 | [mdm-customer.md](../zh/mdm-customer.md) | ✅ Built (`v1.0.0`, all nine gates green) |
| `mdm-product` | 2 | [mdm-product.md](../zh/mdm-product.md) | ✅ Built |
| `erp-inventory` | 2 | [erp-inventory.md](../zh/erp-inventory.md) | ✅ Built |
| `erp-finance` | 2 | [erp-finance.md](../zh/erp-finance.md) | ✅ Built |
| `erp-sales` | 2 | [erp-sales.md](../zh/erp-sales.md) | ✅ Built |
| `infra-authz` | 3 | [infra-authz.md](../zh/infra-authz.md) | ✅ Built (spec source is Design Book Chapter 14) |
| `infra-iam-casdoor` | 3 | [infra-iam-casdoor.md](../zh/infra-iam-casdoor.md) | ✅ Built |
| `infra-workflow` | 3 | [infra-workflow.md](../zh/infra-workflow.md) | ✅ Built |
| `infra-notification` | 3 | [infra-notification.md](../zh/infra-notification.md) | ✅ Built |
| `integration-im-dingtalk` | 3 | [integration-im-dingtalk.md](../zh/integration-im-dingtalk.md) | ✅ Built |
| `infra-print` | 3 | [infra-print.md](../zh/infra-print.md) | ✅ Built (**first Python component**) |
| `infra-bff-mobile` | 3 | [infra-bff-mobile.md](../zh/infra-bff-mobile.md) | ✅ Built (**first TypeScript component**) |
| `frontend-standard` | 3 | [frontend-standard.md](../zh/frontend-standard.md) | ✅ Built |
| `crm-opportunity` | 3 | [crm-opportunity.md](../zh/crm-opportunity.md) | ✅ Built |

> ⚠️ **English versions of the 14 component design plans themselves have not been written yet** — each one only exists in Chinese for now (linked above); translating all fourteen is a substantial follow-on task in its own right, tracked separately, not done in this pass. The table above and this index page are translated; the plans it links to are not, yet.
>
> All 14 of Phase 1–3's components have shipped; see [`AGENTS.md`](../../../AGENTS.md)'s Component Roster for current versions and roles.

## Two more documents here that aren't per-component

| Document | What it is |
|---|---|
| [`_replaceability-map.md`](_replaceability-map.md) *([中文](../zh/_replaceability-map.md))* | A **cross-component** reference — which part of which component can be swapped, who it drags in, and how to swap it. A single component's own design plan §8 only records its own Fork points; this document plots the Fork points of the components that exist so far onto the dependency graph, answering "does this Fork point drag in whatever depends on it" — a question a single design plan can't answer on its own, since it only sees itself. Updated with one new line every time a new component's design plan is written |
| `_调研记录/<phase-number>-<phase-name>.md` | The **full version** of the SOP-R research behind a plan (the design plan's own §8 is the condensed version). **One file per phase, not one file that keeps growing** — naming follows `docs/plans/`'s phase numbering, for the same reason `docs/dev/field-tested-pitfalls-log.md` already follows the "split documents by file" principle. Currently only [`02-阶段二.md`](../_调研记录/02-阶段二.md) exists (the raw findings from checking ERPNext/Odoo/Tryton/metasfresh before `mdm-product`/`erp-inventory`/`erp-finance`/`erp-sales` began) |
