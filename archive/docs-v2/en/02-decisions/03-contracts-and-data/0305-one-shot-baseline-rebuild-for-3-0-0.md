[English](0305-one-shot-baseline-rebuild-for-3-0-0.md) · [中文](../../../zh/02-decisions/03-contracts-and-data/0305-one-shot-baseline-rebuild-for-3-0-0.md)

# 0305 The 3.0.0 rebuild may replace released migrations, once, with no compatibility layers

**Status**: decided; applies to the 3.0.0 sweep only.

## Decision

For the 3.0.0 sweep, and only for it, every component may replace its released migrations with one new baseline, `0001_init`, and break the surfaces listed below without a compatibility layer. The condition that allows it: **no production data exists anywhere**; the demo database `brickkit_db` and the test database `brickkit_test_db` are reset and reseeded.

| What changes at once | Without |
|---|---|
| migrations: UUIDv7 keys ([0306](0306-uuidv7-own-keys.md)), money precision and currency columns ([0301](0301-money-as-strings-lists-by-cursor.md)), `legal_entity_id` on transactional documents, business-date `DATE` columns ([0307](0307-business-dates-and-legal-entity-calendar.md)); no `OWNER TO`, no role or schema names; platform tables left to the SDK | a migration chain from the 2.x schema |
| the REST error body becomes problem details ([0504](../05-runtime/0504-error-model-and-reason-catalogue.md)) | an `error` alias field |
| the event envelope moves to CloudEvents headers ([0505](../05-runtime/0505-cloudevents-envelope-and-aggregate-cursor.md)) | reading the old `X-` headers; derived ids for old events |
| `AUTHZ_URL` and bundle v2 replace `AUTHZ_BUNDLE_URL` and bundle v1 ([0107](../01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)) | a derivation period, a v1 fallback |
| the per-component access tables and their endpoints in erp/inventory and erp/finance are removed ([0207](../02-permissions/0207-scope-assignments-live-in-authz.md)) | a transitional version |
| the SDKs move to v0.6.0 with a new API | wrappers or deprecated aliases for the v0.5.0 API |

Components go to 3.0.0 (Go module path `/v3`), shells to 1.1.0. Registries stay append-only: a permission key that loses its use is marked deprecated, not removed.

## Why

The 3.0.0 design changes key types, column shapes and wire envelopes everywhere at once. With no production data and no shell yet hosting a member, a migration chain or a compatibility layer would cost more than the whole rebuild and would stay in the code for good. Writing down the condition and the exact list keeps the exception from becoming a habit.

## What this rules out

- Using this decision for any later version: a later baseline rebuild or breaking change needs a new decision by a person
- Compatibility shims "just for one version" anywhere in the 3.0.0 sweep
- Keeping a 2.x migration next to the new baseline, or editing a released 3.x migration afterwards
- Applying the rebuild to an environment that holds real data

## Revisit only if

Not applicable: this decision is spent once the 3.0.0 sweep is released. From then on migrations are forward-only and contracts only grow ([0302](0302-contracts-are-additive-only.md)).

Full analysis: [08-schema-evolution.md, Choice](../../04-foundations/08-schema-evolution.md#choice); the key change in [04-identifiers-and-numbering.md, Choice](../../04-foundations/04-identifiers-and-numbering.md#choice).
