[English](reference-implementations.md) · [中文](reference-implementations.zh.md)

# Reference implementations

Business logic in this project starts by looking at how mature software already solves the same problem. A domain model shaped by decades of real deployments has absorbed edge cases a design from scratch will miss, and those surface three months after a customer goes live. This file says how to consult a reference, which one to read for which component, and the one signal to watch for while reading.

## The three-step method

The order matters; never reverse it.

| Step | What to do | Why |
|---|---|---|
| **1. Design your own version first** | Sketch it against this project's constraints before opening any reference | With your own design in hand you see where the difference is; reading with an empty head produces a copy |
| **2. Consult a reference only where you are stuck** | How the domain model is cut, which states exist and which transitions are legal, which fields are mandatory, how the edge cases are handled | This is research, not copying |
| **3. Come back and think it through before writing** | Reconcile what you learned with this project's constraints | The reference's stack and boundaries differ from ours (another language, one process and one database); the point is to borrow the reasoning, never the code |

## Closed-source products and licensing

- **Closed-source products are worth consulting.** You can't read their code, but you can see how they are used: which features customers touch every day, which nobody clicks, which workflows have been complained about for twenty years. That tells you whether something deserves to be its own separately sold component, a judgment that comes before any implementation detail.
- **Licensing**: reading an implementation for its reasoning and re-implementing it independently is not a derivative work. What to avoid is opening the other project's file and transcribing it line by line; the three-step method keeps you clear of that. Code used verbatim comes only from Apache-2.0, MIT or BSD projects, with the original notice kept in a `NOTICE` file.

## Recording what was consulted

Before implementation starts, the component's `docs/design.md` gets a "Reference implementations" section:

```markdown
| Project | Version | Module consulted | What was borrowed | License | Usage |
|---|---|---|---|---|---|
| Odoo | 17.0 | `addons/product/models/product_uom.py` | unit-of-measure conversion factors and rounding | LGPL-3 | Borrowed reasoning |
| A closed-source product | — | — | which conversions are used daily, which never | closed | Borrowed real-world usage |

**Deliberately avoided**: <the anti-pattern found in a reference, and why this project doesn't repeat it>
```

`Usage` takes one of three values: **Borrowed reasoning** (read it, understood why, designed and wrote our own; almost every row), **Borrowed real-world usage** (closed source, or only documentation and UX), **Copied code** (only Apache-2.0 / MIT / BSD, with `NOTICE` and the exact file and section named here).

## Which project to read

| Our component | First reference | What to look at | License | What to avoid |
|---|---|---|---|---|
| mdm/product | Odoo `addons/product` | `uom.uom` and conversion factors; the `tracking` enum (none / lot / serial) | LGPL-3 | — |
| mdm/customer, mdm/supplier | Odoo `addons/base` (`res.partner`) | one partner table for customer, supplier and contact: the trade-off | LGPL-3 | company, person, address and bank account in one table; we split them by data ownership |
| erp/inventory | ERPNext `stock` (Stock Ledger Entry) | an immutable ledger with balances as a projection; batch and serial tracking | GPL-3 | — |
| erp/inventory | Odoo `addons/stock` | the `stock.move` state machine; `stock.quant` reservation semantics | LGPL-3 | quant's double write relies on a database lock under load; we use a conditional update |
| erp/sales, erp/purchase | Odoo `addons/sale`, `purchase` | order states and transitions; quote → order → delivery → invoice kept apart | LGPL-3 | pricing scattered over many `_compute`s; ours lives in one pricing module |
| erp/sales pricing | metasfresh pricing | price lists, discount tiers, promotions | GPL-2/3 | an over-configurable rule engine nobody configures at delivery |
| erp/finance | Tryton `account` | double-entry rigour, accounting periods and period close | GPL-3 | — |
| erp/finance | ERPNext `accounts` | accounting dimensions, naming series | GPL-3 | — |
| erp/manufacturing | Odoo `addons/mrp` | multi-level BOM explosion, work orders, operation reporting | LGPL-3 | MRP tightly coupled to business objects, hard to test alone |
| crm/lead, crm/opportunity | EspoCRM, SuiteCRM | lead → opportunity conversion, stages and win rates, the funnel | GPL-3 / AGPL-3 | — |
| crm/customer | Twenty | ownership, assignment, public and private pools | AGPL-3 | — |
| crm/activity | EspoCRM activities | one activity model for visits, calls and appointments | GPL-3 | — |
| infra/workflow | Camunda, Flowable | only task aggregation and the to-do list | Apache-2.0 | never bring in a BPMN engine: workflow holds no business rules |
| infra/print | Odoo report engine (QWeb) | templates apart from data; template versions | LGPL-3 | tied to wkhtmltopdf; we use WeasyPrint |
| infra/print (ZPL) | Zebra ZPL II Programming Guide | the instruction set (a specification, not code) | vendor documentation | — |
| infra/notification | Novu | notification intent → channel preference → parallel multi-channel delivery | MIT | — |
| infra/bff-mobile | Medusa (modules, workflow SDK) | how saga steps and their compensations are declared | MIT | — |
| hrm/payroll-es | Odoo `hr_payroll` structure | how pay items declare dependencies and are computed in order | LGPL-3 | Spain's IRPF and social-security rules come from the official regulation, never from a copied rate table |
| erp/quality, erp/maintenance, erp/asset | the matching Odoo addons | fields and state machines for routine CRUD | LGPL-3 | — |
| frontend app skeleton | vue-vben-admin | only layout (sidebar, tabs, breadcrumbs), router + access (registration order and guards), the request wrapper (interceptors, error-code messages, deduplication) | MIT | never install it: its routing and access layer is driven by a backend menu table and role codes, ours by installed features |
| frontend page patterns | Ant Design Pro page patterns | the information layout of list, detail, form and multi-step pages | MIT | not a line of its React code |
| frontend tables | vxe-table official examples | editable cells with third-party controls in the edit slot; limits of virtual scroll and frozen columns | see its licence | some capabilities are commercial: check each one against the free tier before relying on it, and write the result in `docs/design.md` |
| overall modularity | Apache OFBiz | a very complete entity model (`OrderHeader`, `OrderItem`, `InventoryItem`, `AcctgTrans`); event-triggered services (SECA) | Apache-2.0, the only large ERP that may be copied directly | Java and heavy XML, doesn't fit our stack |

## Weaknesses to design around

Most open-source ERPs share the same structural weaknesses; reading them is the chance not to repeat them.

| Weakness | How this project avoids it |
|---|---|
| All modules share one process and one database; cross-module JOINs are normal and the boundary is crossed daily | separate processes and schemas, walled off by database roles, not by convention |
| Customisation by runtime patching and hooks, broken by every upgrade | fork the whole component and keep the contract; an upgrade is a deliberate merge |
| Metadata-driven everything (dynamic fields, generic document types), nothing a type checker can see | contracts first (Protobuf, OpenAPI) and statically typed code |
| Reports query live transaction tables and slow the core system | reports go through a summary table or an analytics component |
| Tables grow forever until the system sinks under its history | partitioned from the first migration, with an archival policy |

## Slot-family signal

While comparing references, one situation comes up again and again: **the same feature is implemented differently by several mature systems, and each way is reasonable for a different kind of customer.** That is not a "make it configurable" question, and it is not yet a reason for a family of interchangeable components (a slot family). It is a necessary condition, not a sufficient one; where the divergence lives decides its shape.

- **One implementation clearly better than the rest** → that is the default implementation. Nothing else to do.
- **Several defensible, in a position no component holds a dependency edge on** → a slot family: one member installed per slot (or several side by side in a channel family), every member exposing the identical contract. The positions that qualify are of this kind: the frontend, the identity provider (components reach it through configuration, not a dependency edge), payroll, the notification channels.
- **Several defensible, inside a component others depend on** (every `erp/*` and `crm/*` transactional component) → **not a slot**. A dependent pins that component; swapping it for another member would break the edge. The shape is a **customer fork** of the component (a copy for that customer, same `metadata.id` because dependents' address variables derive from it, those few places changed, versioned normally with `brickkit upgrade` / `make bump-version` moving dependents' pins), or, when the divergence is a few branches with no further variant in sight, an **internal strategy** ([ai-development.md](ai-development.md#when-to-use-a-design-pattern)).

| Feature | Divergence | Conclusion |
|---|---|---|
| Costing method | moving average, FIFO, standard cost with variances, batch actual cost | real, but inside erp/inventory, which others depend on → customer fork |
| Picking strategy | first-expiry-first-out, FIFO, nearest bin, wave picking | same → customer fork |
| Approval routing | org hierarchy, amount tiers, matrix, rule engine | the business component computes the assignee and hands it to infra/workflow, and business components are depended on → customer fork |
| Identity provider | Casdoor, Keycloak | nobody holds an edge on it → slot family |
| Document numbering | sequential, year-month segments, org and type segments | one configuration item |
| Fields on a master record | vendors differ by a few fields | customer fork |

Once a slot family is real (several reasonable variants **and** no dependency edge on the position), in this order:

1. **Record the family before writing any implementation**: its name, the contract every member exposes identically, which customer profile each member serves, which member is installed by default. A new family is a decision record ([../decisions/README.md](../decisions/README.md)).
2. Append each member's ports and schema to `registry/` ([registries.md](registries.md)).
3. Only then design and build each member.

**Never pack several customers' variants into one component behind `if costingMethod == "fifo"`**: every customer's needs then constrain every other's. Inside a depended-on component that is a fork; the one exception is a divergence of two or three branches with no further variant in sight, written as an internal strategy.

Families and forks are also what make customisation cheap: a customer starts from the member, or the fork, closest to what they need.
