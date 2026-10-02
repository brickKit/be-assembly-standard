[English](06-money-quantity-units.md) · [中文](../../zh/04-foundations/06-money-quantity-units.md)

# Money, quantities and units

How amounts, prices, costs, quantities and rates are stored, transmitted and rounded, how a currency travels with every amount, and how units of measure convert. Read it before adding a money, price, quantity or rate column or field, doing arithmetic on one, splitting an amount across lines, or converting between units.

## Scope

Covered: column specifications, currency pairing, ISO 4217 minor units, rounding modes, allocation of remainders, tax rounding, the decimal implementation in each official SDK and the vectors that keep them identical, units of measure and conversions. Not covered: the decimal-string encoding in contracts, which is a decision ([0301](../02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md)); the accounting rules for foreign-currency revaluation, which belong to erp/finance's design; the exchange-rate contract, which belongs to mdm/currency once it exists.

## Choice

- **Fixed-scale `NUMERIC` columns; rounding happens in the SDK, per currency.** A column's scale is its capacity, not its precision: the value stored has already been rounded to what the currency or unit allows.
- **Column specifications**: amount `NUMERIC(19,4)`; unit price and cost `NUMERIC(19,6)`; quantity `NUMERIC(19,6)`; exchange rate `NUMERIC(19,10)`; ratio (discount, tax rate) `NUMERIC(9,6)`.
- **A currency always travels with an amount.** Every document header that carries amounts has `currency CHAR(3)` (ISO 4217 alphabetic code); its lines use the header's currency. Each legal entity has a functional currency. A document in another currency snapshots the exchange rate, its date and its rate type. Ledger entries store the transaction-currency amount and the functional-currency amount.
- **Exchange rates belong to a new component, mdm/currency**: currencies, rate types, daily rates. Like the other mdm hubs, it is read by everyone and calls no one.
- **One decimal implementation per official SDK**, the only place amounts are parsed, formatted, rounded and allocated. The components' own hand-written decimal code is removed. Shared vectors keep Go, Python and TypeScript identical.
- **Rounding**: half away from zero by default (the Chinese tax convention); half-even available. Minor units come from the ISO 4217 table built into the SDK; a project may add cash rounding (for example CHF to 0.05).
- **Allocation** of a total across lines uses the largest-remainder method, so the parts always add up to the total.
- **Tax** is rounded per line or per document; each component that computes tax declares which.
- **Units**: global unit categories with a base unit each; product-specific conversions (one box of product A is 12 pieces, of product B 24) take precedence over global ones; conversion factors are `NUMERIC(24,12)`; each unit can carry its UN/ECE Recommendation 20 code; quantities are rounded by the unit's rounding; a serial-tracked product's quantity is an integer.

**Status**: decided; lands with the 3.0.0 sweep. Today every money column is `NUMERIC(18,2)`, unit prices and standard costs included; only sales orders and opportunities have a currency column; there are no exchange rates; and three components carry decimal code of their own, with different rules (one rejects negative amounts). mdm/currency is built in this round, before the other components move to 3.0.0; it has no registry rows yet.

## Port contract

### Columns

| Kind | Column | Notes |
|---|---|---|
| amount | `NUMERIC(19,4)` | paired with a `currency` on the document header |
| unit price, cost | `NUMERIC(19,6)` | a hardware part at 0.0035 per piece, raw material priced per gram |
| quantity | `NUMERIC(19,6)` | rounded by the unit's rounding |
| exchange rate | `NUMERIC(19,10)` | with `fx_rate_date date` and `fx_rate_type text` on the document |
| ratio | `NUMERIC(9,6)` | discount, tax rate; `0.130000` is 13 % |
| conversion factor | `NUMERIC(24,12)` | milligrams to kilograms and below |
| currency | `CHAR(3)` | ISO 4217 alphabetic, upper case |
| functional-currency amount | `NUMERIC(19,4)` | next to the transaction amount on ledger entries |

A gate fails a new migration whose amount column has a scale below 4.

### On the wire

- Amounts, prices, quantities and rates are decimal strings ([0301](../02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md)): an optional `-`, digits, an optional `.` and digits. No exponent, no thousands separator, no `NaN` or `Infinity`, no leading `+`. Anything else fails with `INVALID_ARGUMENT`.
- An amount is formatted to its currency's minor units: CNY `"12.30"`, JPY `"1230"`, KWD `"1.234"`. A consumer that saw `"12.30"` before still sees `"12.30"`.
- Every message that carries an amount carries `currency` alongside, added as a new field where it is missing ([0302](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)).
- Prices are sent with up to 6 decimals, rates with up to 10, ratios with up to 6.

### Rounding and allocation

| Operation | Rule |
|---|---|
| round an amount | to the currency's minor units (ISO 4217), or to the cash increment where the project configured one; mode `HALF_AWAY_FROM_ZERO` by default, `HALF_EVEN` on request |
| round a quantity | to the unit's rounding |
| allocate a total by weights | largest remainder: floor every share to minor units, then give one minor unit each to the shares with the largest remainders; ties go to the earlier line. The parts always sum to the total |
| tax per line | round each line's tax, the document's tax is the sum |
| tax per document | compute on the document total and round once, then allocate to lines |

### Vectors

`vectors/money/*.json` in the planned `brickKit/be-protocol` repository (not in a conformance suite): each case names an operation (`parse`, `format`, `round`, `allocate`, `tax_line`, `tax_document`, `round_qty`), its inputs, the currency or unit, the mode, and the expected output or error. Every official SDK reads the same files.

## Alternatives

| Question | Option | Strengths | Weaknesses |
|---|---|---|---|
| storage | integer minor units (Stripe: `BIGINT` cents) | exact, fast | the scale must travel with every value; prices and rates still need decimals |
| | **fixed-scale `NUMERIC`** (ERPNext `decimal(21,9)`, Dynamics 365 `numeric(32,16)`) | simple; one column type holds every currency | rounding must happen in the application, by currency |
| | floating point with per-currency rounding (Odoo) | — | known precision problems |
| | SAP's two-decimal CURR with shifted storage for JPY | — | a well-known trap |
| contract | **decimal string** | exact in every language | parsed by hand |
| | `google.type.Money` (units + nanos) | standard proto type | two fields, nine decimals, conflicts with 0301 |
| | integer minor units | compact | the scale is implicit |
| decimal library | Go: `math/big.Rat`, `shopspring/decimal`, `cockroachdb/apd`; Python: the standard `decimal`; TypeScript: `decimal.js`, `big.js` | — | each official SDK picks one; the vectors, not the library, define the behaviour |

## Why this choice

- **Exact everywhere**: strings on the wire, `NUMERIC` in the database, a decimal type in memory; nothing passes through a float.
- **One column shape fits every currency**: four decimals hold the minor units of every ISO 4217 currency in use (0 for JPY and KRW, 3 for KWD, BHD and OMR, 4 for CLF).
- **Rounding is a business rule tied to the currency and to tax**, so it lives in one library with one test set rather than in every component.
- **Overseas and multi-company customers are in scope**, so a currency on every amount and an exchange-rate snapshot on every foreign-currency document are needed from the first table.
- **Existing consumers see no change**: CNY amounts are formatted exactly as before; `currency` is a new field.

## Why not the others

- **Integer minor units**: every value needs its scale beside it, and unit prices and rates are not money and still need decimals, so there would be two representations.
- **Floating point**: loses cents, and rounds differently in Go, Python and TypeScript.
- **`google.type.Money`**: two fields and nine fixed decimals, against 0301's single decimal string.
- **`NUMERIC(18,2)` as today**: cannot hold a price of 0.0035, a three-decimal currency, or a standard cost without accumulating rounding error through cost roll-ups.

## When to switch

- **A column needs more than 15 integer digits** (a cumulative report over very large amounts): widen that one column's precision. Nothing else changes.
- **A currency or a tax regime needs another rounding mode**: add the mode to the SDKs with vectors; components select it by configuration.
- **A project needs cash rounding**: configure the increment; no code changes.

## How to switch

- **A rounding mode or cash increment**: project configuration of the component that rounds (its configuration key or tax-rule declaration), chosen from the modes the vectors cover.
- **The decimal library inside one SDK**: an SDK-internal change; the vectors must stay green, and no component notices.
- **A wider column**: an expand migration in the owning component, released as a version ([0302](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md) for the contract side: the string format already allows more digits).
- **The source of exchange rates**: mdm/currency is fed by an integration component or by hand; consumers read rates from mdm/currency only, so changing the source touches no consumer.

## Conformance tests

The money vectors above, run by every official SDK. Tests to write red first:

- SDK: every vector passes; JPY formats with no decimals and KWD with three; an allocation of 100.00 over three equal weights gives 33.34, 33.33, 33.33 and sums to 100.00; a quantity rounds by its unit's rounding; `NaN`, `Infinity`, exponents and thousands separators are rejected.
- Gate: a new migration with an amount column of scale below 4 fails `make gates`.
- Components, as each moves to the SDK library: the old hand-written decimal code is deleted, and its tests are replaced by the vectors, not kept beside them.

## Decision records

- [0301 Money is a decimal string paired with a currency; lists page by cursor](../02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md): this document is its full analysis: a currency with every amount, the column precision, exchange rates in mdm/currency.
- [0302 Contracts change by adding only](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md): `currency` and functional-currency fields are added, never substituted.
- [0104 A slot family needs several reasonable implementations and no dependency edge](../02-decisions/01-architecture/0104-variants-become-slot-families.md): rounding and allocation are SDK strategies, not slot families.

## Known limits

- **mdm/currency is a prerequisite of the 3.0.0 sweep**: components that convert currencies or revalue read rates from it, so it is released first.
- **Revaluation, realised and unrealised exchange differences** are erp/finance business logic, not designed here.
- **Rounding per line or per document** is a per-component declaration; two components that compute tax on the same document must declare the same one.
- **A column's scale is capacity.** Storing 4 decimals does not mean an amount may carry 4: the currency decides, and only the SDK rounds.
- **Existing contracts gain `currency` additively**; an old consumer that ignores it keeps assuming the deployment's single currency until it is updated.
