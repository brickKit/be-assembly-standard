[English](seed-data.md) · [中文](seed-data.zh.md)

# Seed data

Demo data for local development and testing by hand: fake customers, products, orders, opportunities, vouchers and templates, plus test accounts with different roles and data scopes. One command gives a fresh checkout something to click, query and test. **It is never part of a deployment**: `make seed-data` and `make seed-data-clean` appear in no deployment script and no CI flow, and only run by hand. The rules behind it are in [conventions/data.md](conventions/data.md).

## What gets seeded

Each component owns and seeds its own data (`make seed` in its repository); the root `make seed-data` only calls them in order.

| Component | Data | Amount |
|---|---|---|
| infra/iam-casdoor | four test users, password `DevSeed123!`: `dev.superuser` (every permission, no department), `dev.sales.east` (East China sales), `dev.warehouse.south` (South China warehouse), `dev.finance.viewer` (finance, read only); and the local-only login application `local-dev-seed-app` | 4 users, 1 application |
| infra/authz | four roles (`dev_superuser` with every permission key; `dev_sales_rep`, `dev_warehouse_manager`, `dev_finance_viewer` with subsets) and a department tree (head office → East China, South China), granted to the four users. It looks the users' `sub` up in Casdoor itself | 4 roles, 3 departments |
| mdm/customer | customers across retail, software, food, construction, energy, agriculture, healthcare; `ACTIVE` and `DISABLED`; credit limits from 0 to 1,000,000, including one deliberately tiny; some with past creation dates. Numbers 1–5 are referenced downstream and only ever added to | 12 |
| mdm/product | products for each `TrackingType` (`NONE`, `BATCH`, `SERIAL`); `ACTIVE` and `DISABLED`; unit prices from a few cents to 2,200; some with past creation dates. Numbers 1–5 only ever added to | 12 |
| erp/inventory | its own self-contained set (four products with their own IDs in warehouses WH-EAST and WH-SOUTH: receipt, issue, count surplus, count shortage, one open reservation); when mdm/product's seed exists, 200 units of each of its products; `dev.warehouse.south` granted WH-SOUTH only | 4 own + one per mdm/product product |
| erp/sales | orders by `dev.superuser` (`CONFIRMED`, `SHIPPED`, `CANCELLED`) and by `dev.sales.east` (`DRAFT`, `CONFIRMED`), through its own REST API | 5 |
| crm/opportunity | `seed-opp-1..5` by `dev.superuser` (three `OPEN` at different stages, one `WON`, one `LOST`); `seed-opp-6..10` created with `dev.sales.east`'s real token (same spread, progressing over the last 2–25 days); `seed-opp-11`, a `WON` opportunity for the low-credit customer. Each successful `WON` makes erp/sales create a `CONFIRMED` order owned accordingly; `seed-opp-11`'s order stays `DRAFT` | 11 |
| erp/finance | manual vouchers over receivables, payables, inventory, revenue and cost (single- and multi-line, one reversed); accounting periods in three states (2026-04 closed then locked, 2026-05 closed then reopened, 2026-07 closed); legal-entity access for `dev.superuser` and `dev.finance.viewer` | 5 vouchers, 1 reversal, 3 periods |
| infra/print | two renderable templates: `seed-template-delivery-note` (PDF, a table looped per line) and `seed-template-shipping-label` (ZPL, with barcode instructions); each is rendered once while seeding | 2 |

What the data scopes look like with these accounts: `dev.sales.east` lists only `seed-opp-6..11` and its own department's orders; `dev.warehouse.south` sees only WH-SOUTH stock. Receivables and credit exposure in erp/finance need no seeding: the events of inventory, sales and opportunities fill them.

Every human-readable name starts with `「本地测试」`, so seeded rows are recognisable anywhere; each component's `seed-clean` finds its own rows by that prefix and its fixed idempotency keys.

## Components without seed-clean, or without seed

- **erp/inventory and erp/finance have no `seed-clean`, only `db-reset`.** `inventory_movements` is append-only; a `LOCKED` accounting period can't be turned back by any rpc. Row-by-row deletion can't restore either, so `make seed-data-clean` leaves them alone. To empty them: `make -C components/erp/inventory db-reset` or `make -C components/erp/finance db-reset` (`migrate down`, then `up`). That empties **all** of the component's data, not just the seeded part.
- **infra/print has no `seed-clean`**: templates are versioned, and reseeding adds a version.
- **infra/workflow and infra/notification have no `make seed`.** Workflow's task commands are deliberately not exposed over REST, and notification has no write rpc at all: records come only from events. Their data comes from a real business failure instead: `seed-opp-11` wins with a customer over its credit limit, erp/sales refuses to confirm the order and opens an exception task in infra/workflow (assigned to East China), and that task produces a notification record.
- **integration/im-dingtalk has no seed data**: it talks to a real DingTalk team and real phones; fake credentials would test nothing and real ones would message someone on every run.

## How to use

```bash
make seed-data          # load everything; safe to rerun (fixed idempotency keys)
make seed-data-clean    # undo what can be undone (see the previous section)
make -C components/erp/inventory seed   # one component, with what it depends on
```

Log in through the normal Casdoor login page of the frontend as `dev.superuser` / `DevSeed123!`, or as one of the other three users to see a different role and data scope.

## Test accounts and the ROPC application

Creating opportunities, orders and vouchers needs a real login: the owner and department come from the caller's token. infra/iam-casdoor's `make seed` therefore creates `local-dev-seed-app`, an application with the Resource Owner Password Credentials grant that exists **only in local environments**. Seed scripts exchange a test user's name and password for a real token and create data through the real REST APIs, never by writing to the database, so the seed also exercises the real authentication path.

The production application (`brickkit-app`) never enables the password grant; the seed creates its own application and never touches that one.

## Prerequisites

- The whole project is up (`brickkit up`); each seed script checks the ports and health checks it needs and stops with an error before writing half a dataset.
- `curl`, `python3` and `docker` on the host. Scripts that call gRPC run the `fullstorydev/grpcurl` image; no local `grpcurl` is needed.
- Any row of the table can run on its own (`make -C components/<scope>/<name> seed`); it first seeds what that component depends on.

## What this is not

- **Not test data.** Seed data goes into `brickkit_db`, the database the running project uses. Automated tests use `brickkit_test_db` (`make test-db-init`): same schemas, data never shared. What you click in the frontend is never touched by a component's tests, and tests that write shared reference rows (warehouse balances, legal-entity posting sequences) never change the demo.
- Not a CI fixture. It runs by hand.
