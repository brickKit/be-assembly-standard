[English](05-time-and-calendars.md) · [中文](../../zh/04-foundations/05-time-and-calendars.md)

# Time and calendars

How the project stores and transmits time, which day a document belongs to, whose time zone decides it, and how fiscal periods and years are defined. Read it before adding a date or timestamp column, writing SQL that mentions "today", booking anything into a period, or adding a date to an event or a contract.

## Scope

Covered: instants and business dates, the business time zone of a legal entity, the database session time zone, how "today" reaches SQL, business dates in events, fiscal periods and fiscal years, how dates are displayed. Not covered: deadlines and timeouts ([16-deadlines-and-retries.md](16-deadlines-and-retries.md)); retention periods and partition windows ([09-data-lifecycle.md](09-data-lifecycle.md)); legal entities as a data dimension ([07-tenancy.md](07-tenancy.md)).

## Choice

Two kinds of time, never mixed:

- **An instant** is a point on the timeline (`created_at`, `posted_at`, `confirmed_at`). Stored as `timestamptz`, sent in UTC.
- **A business date** is the day a document belongs to (document date, posting date, due date, price effective date). Stored as `DATE`, sent as `YYYY-MM-DD`, never converted between time zones.

And the rules that connect them:

- **The business time zone belongs to the legal entity**: an IANA name, default `Asia/Shanghai`. A business date is the civil date of an instant in that legal entity's zone.
- **The fiscal year start month belongs to the legal entity**: default 1 (January). Fiscal periods are rows with a start and end date.
- **The database session time zone is always UTC.** Business SQL never asks the database what day it is; the SDK computes "today" for the legal entity and passes it as a parameter.
- **Events carry the business dates of their document.** A consumer books by those dates, never by the moment it processes the event.
- **Opening a fiscal year is a command**, not a yearly migration: it creates the year's periods (and their partitions) for one legal entity, from its start month.
- **Display**: a business date is shown as it is. An instant is shown in the legal entity's zone with the zone marked. There is no per-user time zone preference ([0404](../02-decisions/04-frontend/0404-four-user-preferences.md)).

**Status**: decided; lands with the 3.0.0 sweep. Legal entities and their calendar attributes come from mdm/org, a new component built in this round before the other components move to 3.0.0; `BUSINESS_TIMEZONE` stays the deployment default that cron schedules use ([19](19-background-jobs.md)). Today erp/finance takes the posting date from the processing time in UTC and erp/sales evaluates price effective dates against the database's `CURRENT_DATE`; both are known bugs fixed in the sweep ([Known limits](#known-limits)).

## Port contract

### Column types

| What | Column | Example |
|---|---|---|
| instant | `timestamptz` | `created_at`, `posted_at` |
| business date | `date` | `document_date`, `posting_date`, `due_date`, `date_start`, `date_end` |
| fiscal period | a row: legal entity, fiscal year, period number, `start_date date`, `end_date date` (inclusive), label, status | label `2026-10` is display only |

### On the wire

| What | proto | REST and events |
|---|---|---|
| instant | `google.protobuf.Timestamp` | RFC 3339 in UTC with `Z`: `2026-10-01T23:30:00Z` |
| business date | `google.type.Date` | `"2026-10-02"` (OpenAPI `format: date`) |

A business date is never sent as an instant at midnight: midnight in which zone is exactly the ambiguity it exists to remove.

### Legal-entity calendar

| Attribute | Type | Default | Where it lives |
|---|---|---|---|
| business time zone | IANA zone name | `Asia/Shanghai` | the legal entity in mdm/org |
| fiscal year start month | integer 1–12 | 1 | the legal entity's calendar, set by the open-fiscal-year command |

The conversion `business date = civil date of (instant) in (legal entity's zone)` has exactly one implementation per official SDK, checked by shared vectors. It handles daylight saving time; the database is never asked to do it. Every SDK MUST embed its time zone data (Go `time/tzdata`, Python the `tzdata` package, Node full ICU), so the answer never depends on the image's zone files; legal entities store canonical IANA names, never link names such as `Asia/Calcutta`.

**Without mdm/org (degraded mode).** When mdm/org is not installed (`MDM_ORG_ENDPOINT` does not exist), the component does not crash: every legal entity uses `BUSINESS_TIMEZONE` as its zone and fiscal year start month 1, and the runtime flags the degraded calendar in `/_be/info`. Once mdm/org is installed, its legal-entity calendars replace these values.

### SQL

- The connection's `TimeZone` is UTC and is never changed, at session or transaction level.
- Business SQL does not use `CURRENT_DATE`, `now()::date`, `date_trunc(…, now())`, or `::date` applied to a `timestamptz`. "Today" and every business-date boundary are computed by the SDK and passed as parameters. A gate scans migrations and repository SQL for these forms.
- A `DATE` is compared with a `DATE`. Comparing a `DATE` with a `timestamptz` casts the date to midnight in the session's zone, which is the month-end bug described in [Known limits](#known-limits).
- To select instants within a business-date range, the SDK turns `[first day, last day]` into a half-open instant range `[start, end)` in the legal entity's zone and passes two `timestamptz` parameters.

### Events

- Every event about a dated document carries that document's business dates as fields of the payload (`document_date`, `posting_date`, …), added as optional fields ([0302](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)).
- A consumer that books by date uses those fields. When an older event lacks them, it falls back to the business date of the event's occurrence time in the legal entity's zone, never to the time it processes the event. A replay from the dead-letter queue across a month boundary therefore books into the original period.

### Fiscal periods

- A posting finds its period by `start_date <= business_date AND business_date <= end_date`, both sides `DATE`, for the document's legal entity.
- The period label is not used for lookup: with an April start, the label `2026-04` is the first period of fiscal year 2026/27.
- Opening a fiscal year takes the legal entity, the fiscal year and, the first time, the start month; it is idempotent and reports the periods it created.

## Alternatives

| Question | Options |
|---|---|
| whose time zone decides the day | the user's (common in SaaS); the company's (common in ERP: everyone sees the same day for a document); the server's; UTC |
| where the conversion happens | the database session time zone; the application, per legal entity |
| how a business date is stored | `DATE`; a `timestamptz` at midnight; text |
| how fiscal years are defined | calendar months only; a configurable start month; 13 periods; 4-4-5 week calendars. Mainstream ERPs use a period table with date ranges |

## Why this choice

- **One document, one day, for everyone.** A sales order dated 1 October is dated 1 October for the warehouse, for finance and for the auditor, whatever their location.
- **Legal entities may sit in different countries.** Group companies are in scope now, and overseas customers are on the roadmap, so the zone cannot be a deployment constant forever.
- **Session state is unreliable on a shared pool.** In a shell many members share connections; a session-level `SET TIME ZONE` is the same hazard as a `SET` without `LOCAL`.
- **A `DATE` has no zone**, so it cannot be shifted by a conversion nobody noticed.
- **Period rows with date ranges** express any fiscal calendar, including years that do not start in January.

## Why not the others

- **The user's time zone**: two users would see the same voucher on different dates, and which period a document falls into would depend on who looks.
- **The database session time zone per legal entity**: session state on pooled connections, and one shell serves several legal entities at once.
- **A `timestamptz` at midnight**: shifts by a day when read in another zone; that is the bug, not a representation.
- **Calendar months only**: cannot express an April-start fiscal year, and the label `2026-04` then misleads.

## When to switch

- **A legal entity needs 13 periods or a 4-4-5 calendar**: the period rows already carry date ranges; the open-fiscal-year command gains a calendar pattern parameter, added without breaking.
- **Users need instants in their own zone**: a frontend display preference only, which means revisiting 0404. Business dates stay as they are.
- **A legal entity moves to another zone**: a data change, not a design change (below).

## How to switch

- **A legal entity's time zone**: change it on the legal entity in mdm/org. Business dates computed from then on use it; existing documents keep their dates.
- **The fiscal year start month**: pass it when opening the next fiscal year. Years already open are unchanged.
- No component code changes in either case: components ask the SDK for business dates and look periods up by date.

## Conformance tests

Shared vectors in `vectors/calendar/` of `be-protocol` (`business_date.json`, `bounds.json`, `fiscal.json`): instant plus zone gives business date, including daylight-saving boundaries (for example `America/New_York`) and the Beijing hours 00:00–08:00, which are the previous day in UTC. Every official SDK must give the same answers. Each vector file names the tz release its expected values were computed with; when the tz data changes, the vectors are regenerated and cross-checked across languages before an SDK embeds the new release.

Tests to write red first:

- erp/finance: a posting on the afternoon of the last day of a month lands in that month; a posting at 07:30 Beijing time on 1 October lands in October; an automatic entry books by the event's `posting_date`, not by the time it was consumed; an old event replayed after the month closed books into its original period.
- erp/sales: a price effective from 1 October applies from midnight Beijing time, not from 08:00.
- SDK: the business-date conversion across a daylight-saving change; "today" for two legal entities in different zones at the same instant.
- Gate: `CURRENT_DATE`, `now()::date` or `::date` on a `timestamptz` in a migration or repository query fails `make gates`.

## Decision records

- [0307 Business dates follow the legal entity's calendar](../02-decisions/03-contracts-and-data/0307-business-dates-and-legal-entity-calendar.md): this document is its full analysis.
- [0308 A tenant is a deployment](../02-decisions/03-contracts-and-data/0308-tenant-is-the-deployment.md): legal entities are a dimension inside one deployment, each with its own calendar.
- [0404 Users own four preferences](../02-decisions/04-frontend/0404-four-user-preferences.md): users have no time zone preference; instants are shown in the legal entity's zone.
- [0302 Contracts change by adding only](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md): business-date fields join existing events as optional fields.

## Known limits

- **mdm/org is a prerequisite of the 3.0.0 sweep**: no component books by legal-entity calendar before it is released. How legal entities in mdm/org relate to departments in the IAM directory is settled in mdm/org's own design.
- **Without mdm/org every legal entity shares one calendar**: `BUSINESS_TIMEZONE` and a January fiscal year, flagged in `/_be/info`.
- **Changing a legal entity's zone does not re-date history**; documents keep the business dates they were given.
- **Only month-based fiscal calendars** are produced by the open-fiscal-year command for now; 13-period and 4-4-5 calendars need the pattern parameter.
- **Two known bugs remain until the sweep**: erp/finance takes the posting date from the processing time in UTC and compares a `DATE` with a `timestamptz`, so postings after 00:00 UTC on the last day of a month land in the next month, Beijing postings between 00:00 and 08:00 land on the previous day, and a delayed or replayed event lands in the period of its processing; erp/sales evaluates price effective dates with the database's `CURRENT_DATE` in UTC, so a price effective 1 October applies from 08:00 Beijing time.
