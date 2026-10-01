[English](0012-variants-become-slot-families.md) · [中文](0012-variants-become-slot-families.zh.md)

# 0012 Several reasonable implementations mean a new slot family

## Decision

When mature systems implement a feature in genuinely different ways, each right for a different kind of customer (costing method, picking strategy, approval routing), the feature becomes a slot family: one component per variant, all with an identical contract, and the customer picks one at assembly time. It is not a configuration switch inside one component. The family is designed and registered before any member is implemented, and no other component may hold a dependency edge on a member.

## Why

A switch packs every customer's variant into one codebase, where a change made for one customer can break another. A family keeps each variant separate and lets a customer fork the member closest to what it needs. If one implementation is clearly better than the others, it is simply the default and no family is needed.

## What this rules out

- `if costingMethod == "fifo"` inside a component
- "Add a setting so customers can choose the algorithm"
- Strategy flags that gain a new value for each new customer
- The opposite mistake: making a family out of a plain setting (a document numbering scheme is one config key) or out of "a few more fields on the master record" (that is a fork)
- Another component depending directly on one member of a family

## Revisit only if

The variants converge, in practice, on one implementation — then the family shrinks to it.
