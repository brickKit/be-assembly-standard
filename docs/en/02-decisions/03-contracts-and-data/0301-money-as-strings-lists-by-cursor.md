[English](0301-money-as-strings-lists-by-cursor.md) · [中文](../../../zh/02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md)

# 0301 Money is a decimal string paired with a currency; lists page by cursor

**Status**: revised for 3.0.0 (currency pairing, column precision, exchange rates); decided, lands with the 3.0.0 sweep.

## Decision

**Money.** Every money field in every contract (proto, OpenAPI, event schema) is a decimal encoded as a string, and every amount travels with its currency:

| Value | Column | On the wire |
|---|---|---|
| amount | `NUMERIC(19,4)` | decimal string |
| unit price, cost, quantity | `NUMERIC(19,6)` | decimal string |
| exchange rate | `NUMERIC(19,10)` | decimal string |
| ratio (discount, tax rate) | `NUMERIC(9,6)` | decimal string |
| currency | `CHAR(3)`, the ISO 4217 alphabetic code, on every document header that carries amounts | `currency` |

Each legal entity has a functional currency; a document in another currency snapshots the exchange rate, its date and its rate type, and ledger entries store both the transaction-currency and the functional-currency amount. Exchange rates belong to `mdm/currency`, read by everyone like every mdm hub. Parsing, formatting, rounding and allocation happen only in the official SDKs' decimal implementation, kept identical by shared vectors.

**Lists.** Every `List` operation pages by an opaque cursor (`cursor`, `page_size`, `next_cursor`) and has no `offset` field.

## Why

A `double` loses precision, and Go, Python and TypeScript each round it differently; a decimal string arrives exactly as it was sent. An amount without its currency is meaningless once group companies and overseas customers are in scope, and four decimals hold the minor units of every ISO 4217 currency in use. Rounding is a business rule tied to currency and tax, so it lives in one library with one test set. Deep offsets get slower with every page and let a client ask for page 1000; with no `offset` field, deep paging cannot even be expressed in the contract.

## What this rules out

- `double` / `float` amounts, or a JSON number for an amount
- An amount field or column without its currency; `NUMERIC(18,2)` for prices or costs
- Hand-written rounding or decimal code inside a component
- Exchange rates kept in a business component instead of `mdm/currency`
- Adding `offset`, `page` or `page_number` to a `List` request
- "Jump to page N": narrow the result with filters (date range, status, search) instead

## Revisit only if

Never for money as a string with its currency; a column that needs more than 15 integer digits widens that one column. Never for paging either: a list expected to stay small still takes a cursor, so every `List` works the same way.

Full analysis: [06-money-quantity-units.md, Choice](../../04-foundations/06-money-quantity-units.md#choice); cursors in [04-identifiers-and-numbering.md, Cursors](../../04-foundations/04-identifiers-and-numbering.md#cursors).
