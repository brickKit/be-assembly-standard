[English](0012-variants-become-slot-families.md) · [中文](0012-variants-become-slot-families.zh.md)

# 0012 A slot family needs several reasonable implementations and no dependency edge

## Decision

A feature becomes a slot family — one component per variant, all with an identical contract, the customer installs one (`slot`) or several (`channel`) at assembly time — only when both conditions hold: (a) mature systems implement it in genuinely different ways, each right for a different kind of customer, and (b) no component holds a dependency edge on that position. Real slot positions are of this kind: the frontend (`slot:frontend`), identity (`slot:iam`), payroll by country (`slot:payroll`) and external channels such as IM (`channel:im`). When (a) holds but (b) fails — the normal case for divergences inside transactional components (costing method, picking strategy, approval routing, period closing, pricing) — the standard component ships one default implementation, and a customer who needs another gets a customer fork of that component. If the divergence is only two or three branches with no further variant in sight, it may stay inside the component as an internal strategy. The family is designed and registered before any member is implemented.

## Why

A dependency edge names an exact component id, and the injected variable carries the implementation's name, so a position other components depend on cannot be swapped by assembly — swapping it would mean changing every dependent. A configuration switch, on the other side, packs every customer's variant into one codebase, where a change made for one customer can break another. A fork keeps each customer's divergence in its own copy, starting from the closest standard component. If one implementation is clearly better than the others, it is simply the default.

## What this rules out

- "Let customers choose FIFO or weighted-average costing" as a slot family (`slot:costing`, a separate costing or picking component) — those positions sit inside `erp/inventory`, which other components depend on; the answer is one default method in the standard component and a customer fork for a customer who needs another
- `if costingMethod == "fifo"` branches that grow with each new customer, or "add a setting so customers can choose the algorithm" — except a small internal strategy of two or three branches with no further variant in sight
- Another component depending directly on a member of a family (on `infra/iam-casdoor` instead of verifying tokens locally)
- Making a family out of a plain setting (a document numbering scheme is one config key) or out of "a few more fields on the master record" (that is a fork)

## Revisit only if

A divergent position stops having any dependents — then it can become a slot family; or the variants of a family converge, in practice, on one implementation — then the family shrinks to it.
