[English](0307-business-dates-and-legal-entity-calendar.md) · [中文](../../../zh/02-decisions/03-contracts-and-data/0307-business-dates-and-legal-entity-calendar.md)

# 0307 Business dates follow the legal entity's calendar

**Status**: decided; lands with the 3.0.0 sweep.

## Decision

Two kinds of time, never mixed:

| Kind | Examples | Column | On the wire |
|---|---|---|---|
| instant | `created_at`, `posted_at` | `timestamptz` | RFC 3339 in UTC |
| business date | document date, posting date, due date, price effective date | `DATE` | `YYYY-MM-DD`, never converted between zones |

- **Each legal entity has a business time zone** (an IANA name, default `Asia/Shanghai`) **and a fiscal year start month** (default 1). Both come from `mdm/org`. A business date is the civil date of an instant in its legal entity's zone.
- **The database session time zone is always UTC**, and business SQL never asks the database what day it is: the SDK computes "today" for the legal entity and passes it as a parameter.
- **Events carry the business dates of their document**; a consumer books by those dates, never by the moment it processes the event.
- **Fiscal periods are rows** with a start and an end date; opening a fiscal year is a command for one legal entity, not a yearly migration.
- **Display**: a business date is shown as it is; an instant in the legal entity's zone, with the zone marked. There is no per-user time zone. `BUSINESS_TIMEZONE` remains the deployment default that cron schedules use.

## Why

One document belongs to one day for everyone: the warehouse, finance and the auditor see the same date wherever they are. Group companies may sit in different countries, so the zone cannot be a deployment constant. A session-level time zone is unsafe on a shared pool, and a `DATE` cannot be shifted by a conversion nobody noticed. Before 3.0.0, finance took the posting date from the processing time in UTC, so month-end vouchers and those posted between 0:00 and 8:00 Beijing time landed on the wrong day.

## What this rules out

- `CURRENT_DATE`, `now()::date` or a session `SET TIME ZONE` in business SQL
- A business date stored as `timestamptz`, or derived from the time an event was processed
- One time zone for the whole deployment applied to every legal entity's documents
- A yearly migration that creates the next fiscal year's periods
- A per-user time zone preference ([0404](../04-frontend/0404-four-user-preferences.md))

## Revisit only if

A legal entity needs 13 periods or a 4-4-5 calendar (the open-fiscal-year command gains a calendar pattern, as an addition), or users need instants in their own zone (a display preference only, which reopens 0404).

Full analysis: [05-time-and-calendars.md, Choice](../../04-foundations/05-time-and-calendars.md#choice).
