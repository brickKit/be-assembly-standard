[English](0010-money-as-strings-lists-by-cursor.md) · [中文](../../../zh/02-decisions/03-contracts-and-data/0010-money-as-strings-lists-by-cursor.md)

# 0010 Money is a decimal string; lists page by cursor

## Decision

Every money field in every contract (proto, OpenAPI, event schema) is a decimal encoded as a string. Every `List` operation pages by cursor and has no `offset` field.

## Why

A `double` loses precision, and Go, Python and TypeScript each round it differently; a decimal string arrives exactly as it was sent. Deep offsets get slower with every page and let a client ask for page 1000; with no `offset` field, deep paging cannot even be expressed in the contract.

## What this rules out

- `double` / `float` amounts, or a JSON number for an amount
- Adding `offset`, `page` or `page_number` to a `List` request
- "Jump to page N" — narrow the result with filters (date range, status, search) instead

## Revisit only if

Never for money. Never for paging either: a list expected to stay small still takes a cursor, so every `List` works the same way.
