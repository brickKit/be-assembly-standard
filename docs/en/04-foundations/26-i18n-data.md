[English](26-i18n-data.md) · [中文](../../zh/04-foundations/26-i18n-data.md)

# Languages in data

Which stored data exists in several languages and how it is stored, which standard codes replace stored names, how a server learns the language it must write in, and which outputs a server renders in a language at all. For whoever adds a name field to master data, prints a document, sends a notification, or is asked for "an English product name on export orders".

## Scope

- **In:** translatable columns on master and reference data and their contract fields; picking a value for a language; the document language and name snapshots; standard codes for language, country, currency, time zone and unit; where the server-side language comes from; the deployment's default language; the language of error bodies (by reference).
- **Out:** interface strings and formatting in the frontend ([03-frontend.md](../01-conventions/03-frontend.md#internationalisation)); the error model and its catalogue ([15-user-api-and-errors.md](15-user-api-and-errors.md)); time zones and business dates ([05-time-and-calendars.md](05-time-and-calendars.md)); currencies, amounts and units ([06-money-quantity-units.md](06-money-quantity-units.md)); search over translated names ([25-search.md](25-search.md)).

## Choice

- **A translatable short text gets a sibling JSONB column**: `name` keeps the value in the deployment's default language, `name_i18n` holds the other languages. Additive: every existing reader of `name` keeps working.
- **Contracts gain the map beside the field** (`map<string, string> name_i18n`); the caller picks the value for its language, with a fixed fallback chain.
- **Codes are stored, names of codes never are**: BCP 47 languages, ISO 3166 countries, ISO 4217 currencies, IANA time zones, UN/ECE Recommendation 20 units. The frontend renders their names.
- **The server writes language only where no frontend is involved**: notifications and printed documents, in the recipient's language. Everything a user sees in the app is translated by the frontend.
- **The server learns a language from data, never from `Accept-Language`**: a user's `locale` from the identity provider, a customer's or supplier's `preferred_language` from master data, a document's `language` from the document.
- **Errors carry machine reasons**; the frontend translates them from the catalogue ([15](15-user-api-and-errors.md#the-reason-catalogue)).
- **One deployment default language**, shared key `DEFAULT_LOCALE`, default `zh-CN` (a protocol key, `be-protocol` `schemas/config-keys.yaml`; [24](24-config-and-secrets.md)).

**Status**: in place: master data has a single `name TEXT` (customers, products, units, categories, accounts, opportunity stages); the frontend is complete in Chinese and English, and the language is a frontend preference kept in the browser; no server knows a user's language. Decided (the 3.0.0 sweep): the error model and catalogue ([15](15-user-api-and-errors.md)), the `locale` claim and its place in directory events ([21-identity-provider.md](21-identity-provider.md)), the standard codes, `DEFAULT_LOCALE` (needed by the error bodies' default-language `title` and `detail`). Later (wanted, not urgent): the `_i18n` columns and contract fields, `preferred_language`, the document `language`, the frontend writing the user's language back to the identity provider.

## Port contract

### Language tags

- BCP 47 tags in canonical case (`zh-CN`, `en`, `zh-Hant-TW`), stored as `TEXT`.
- **Matching** is RFC 4647 lookup: the requested tag, then the tag with its last subtag removed until only the language is left (`zh-Hant-TW` → `zh-Hant` → `zh`), then the default language. The catalogue keys of [15](15-user-api-and-errors.md#the-reason-catalogue) (`zh`, `en`) match by the same rule.
- `DEFAULT_LOCALE` is one value for the whole deployment, written once in `config/vars.yaml`; changing it after data exists is a data migration, not a setting.

### Translatable columns

| Column | Type | Rule |
|---|---|---|
| `name` | `TEXT NOT NULL` | the value in `DEFAULT_LOCALE`; required; what every existing consumer reads |
| `name_i18n` | `JSONB NOT NULL DEFAULT '{}'` | `{"<tag>": "<text>"}` for other languages; an entry for the default tag is ignored on read and dropped on write, because `name` is authoritative for it |

- **Which fields**: short display texts of master and reference data: names, short descriptions, unit and category names, account names, stage names. Not: free text on documents (notes, addresses), people's names, anything a user types once in one language.
- **JSONB is opaque storage** ([03-database.md](03-database.md#capability-list)): never filtered, sorted or indexed by key in SQL. Search covers every language through `search_text` ([25](25-search.md#the-column)); sorting is by `name`.
- The same pair works for any field: `description` / `description_i18n`.

### On the wire

- **gRPC**: `string name = N; map<string, string> name_i18n = M;` added to the entity message; `BatchGet` returns both, and each caller picks.
- **REST**: the same two members in JSON. A write that sends `name_i18n` replaces the whole map.
- **Events**: master-data events carry `name_i18n` with `name`, so snapshots copy both ([11-consistency-across-components.md](11-consistency-across-components.md)).
- **Picking**: walk the matching chain above over `name_i18n`, then fall back to `name`. Every official SDK implements the same chain; a shared vector set in be-protocol for it is proposed.

### Documents and snapshots

- A transaction document that is printed or sent to a partner carries `language TEXT NOT NULL` (BCP 47), defaulting to the partner's `preferred_language`, else `DEFAULT_LOCALE`.
- Line snapshots of names (product name on an order line) are taken in the document's language when the line is created, and never change afterwards: an export order prints the English product name it was created with.
- Master data of partners gains `preferred_language` (mdm/customer, mdm/supplier), additive.

### Where a server-side language comes from

| Output | Language | Source |
|---|---|---|
| a notification to a user | the user's language | `locale` in the identity provider's directory events, copied into the notification component's snapshot; else `DEFAULT_LOCALE` |
| a printed document | the document's language | the document's `language` |
| a message to a customer or supplier contact | the partner's language | `preferred_language` in master data |
| an export file a user requested (column headers) | the requesting user's language | the `locale` claim of the token on the request |
| an error body's `title` and `detail` | the default language | `DEFAULT_LOCALE`; for logs and as a last resort only ([15](15-user-api-and-errors.md#the-error-body)) |
| every screen | the user's choice | the frontend ([0404](../02-decisions/04-frontend/0404-four-user-preferences.md)); written back to the identity provider (planned `PUT /api/me/locale`) so servers see it |

`Accept-Language` is not used anywhere. A token's `locale` can be up to one access-token lifetime (600 s) behind a change.

### Standard codes

| Thing | Standard | Column | Example | Names rendered by |
|---|---|---|---|---|
| language | BCP 47 | `TEXT` | `zh-CN` | the frontend (CLDR, `Intl.DisplayNames`) |
| country or region | ISO 3166-1 alpha-2 | `CHAR(2)` | `CN` | the frontend (CLDR) |
| subdivision | ISO 3166-2; GB/T 2260 for Chinese administrative divisions | `TEXT` | `CN-SH` | the frontend, or a reference table that is itself translatable |
| currency | ISO 4217 alphabetic | `CHAR(3)` | `CNY` | the frontend; minor units from mdm/currency ([06](06-money-quantity-units.md)) |
| time zone | IANA | `TEXT` | `Asia/Shanghai` | the frontend ([05](05-time-and-calendars.md)) |
| unit of measure | UN/ECE Recommendation 20 | `TEXT` | `KGM` | the unit's own translatable name in mdm/product |

A code column is a reference by standard code ([04-identifiers-and-numbering.md](04-identifiers-and-numbering.md)); it never stores "China" or "中国".

## Alternatives

| Approach | Used by | Strengths | Weaknesses |
|---|---|---|---|
| **A JSONB translation column beside the base column** (chosen) | Odoo 16 and later (moved from a translation table to JSONB columns) | no join; one row read gives every language; additive | no index or sort per language in SQL |
| A text table per entity, `<entity>_texts(id, lang, name)` | SAP (MAKT and the like), Dynamics 365 | indexable and sortable per language | a join on every read; easy for a developer or an AI to forget |
| One column per language (`name_en`, `name_zh`) | small systems | trivial | a migration for every new language |
| A central translation service | some suites | one place | a dependency from every component, against component boundaries |
| The server translates by `Accept-Language` | classic web applications | the client shows what it gets | every component keeps every language's text; the language is a frontend preference |
| Message keys stored in data, translated in the frontend | some SaaS products | no translations in the database | master data is entered by customers, not by developers |

## Why this choice

- **Additive and local**: one column more in the owner's table, one map more in its contract; no new component, no join, no consumer breaks ([0302](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)).
- **The contract is the map, not the storage**: a table can move to a text table later without any caller noticing.
- **Codes keep data language-free**: a country or a currency never needs translating in the database.
- **Text is produced where the language is known**: the frontend for users on screen, the server only for outputs that leave without a frontend.

## Why not the others

- **Text tables**: a join on every list and every `BatchGet`, for a feature (sorting by a non-default language in SQL) nobody has asked for.
- **A column per language**: a schema change every time a customer adds a language.
- **A translation service**: every component would depend on it, and a component could no longer run alone.
- **Server-side translation**: puts every language into every component and contradicts the language being the user's choice in the frontend.
- **Message keys in data**: customers type their own product names; there is no key to translate.

## When to switch

- **One entity needs more than about ten languages**, or **sorting or an index per language** in SQL: move that table to a text table.
- **Free text on documents must be translated**: that is a business feature (a translation workflow), not a storage change.
- **Server-rendered text is needed beyond notifications, print and exports**: add a localised message member to errors, as an addition ([15](15-user-api-and-errors.md#when-to-switch)).

## How to switch

1. Create the text table in the owner's schema and backfill it from `name_i18n` (a resumable job, [19-background-jobs.md](19-background-jobs.md)).
2. Read and write through the text table; keep `name_i18n` in the contract, now assembled from the table.
3. Drop the JSONB column in a later version (expand, then contract). Callers, events and the frontend do not change.

## Conformance tests

Tests written red first:

- each official SDK: the fallback chain (`zh-Hant-TW` → `zh-Hant` → `zh` → `name`); an entry for the default tag is ignored; an unknown tag falls back to `name`;
- mdm/product, once the columns exist: `BatchGet` returns `name_i18n`; an update replaces the map; the updated event carries it;
- erp/sales: an order created in `en` snapshots the English product name; a later change of the product's English name leaves the order line unchanged;
- infra/print: a document renders in its `language`; infra/notification: a notification uses the recipient's `locale`, falling back to `DEFAULT_LOCALE`;
- the error model's tests in [15](15-user-api-and-errors.md#conformance-tests) cover the error language.

No port suite: nothing here is replaceable infrastructure.

## Decision records

- [0404 Four user preferences](../02-decisions/04-frontend/0404-four-user-preferences.md): the language is the user's choice in the frontend; a revision is planned so that the choice is also written to the identity provider for server-side text.
- [0302 Contracts change by adding only](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md): `name_i18n` and `preferred_language` are additions.
- [0203 The token carries identity only](../02-decisions/02-permissions/0203-jwt-carries-identity-only.md): its planned revision adds `locale` ([21](21-identity-provider.md)).
- [0504 One error object, identified by a reason from a catalogue](../02-decisions/05-runtime/0504-error-model-and-reason-catalogue.md): errors carry machine reasons; the frontend translates.

## Known limits

- **Sorting by name follows the default language**; a list in another language is sorted by `name`, not by the translated value.
- **Free text is in one language**: notes, addresses and people's names are stored as typed.
- **No machine translation**; a missing translation shows the default-language value.
- **Snapshots keep the translation they were taken with**; correcting a product's English name does not change orders already created.
- **A changed user language reaches server-side text only after the token refreshes** (up to 600 s), and only once the frontend writes it back.
- **Right-to-left languages** are not considered by the frontend today.
