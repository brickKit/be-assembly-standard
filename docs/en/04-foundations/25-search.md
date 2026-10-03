[English](25-search.md) · [中文](../../zh/04-foundations/25-search.md)

# Search

How a user finds a record by typing part of a code, a name, its pinyin or its initials: the `q` parameter of a component's own list, the normalised search column behind it, how the index is chosen from the extensions the database has, how results are ranked, and the direction for a later search across components. For whoever adds `q` to a list, changes what is searchable, or proposes a search engine.

## Scope

- **In:** `q` on a component's own `List`; the `search_text` column and its normalisation (case, width, pinyin, initials); index strategies chosen by probing extensions; ranking and paging with `q`; escaping; the shared vectors that keep every SDK identical; the global search slot family.
- **Out:** the data-scope predicate that `q` is combined with ([20-authorization-provider.md](20-authorization-provider.md)); cursors and paging fields ([15-user-api-and-errors.md](15-user-api-and-errors.md#lists)); translated names as a source of search text ([26-i18n-data.md](26-i18n-data.md)); searching inside attachment contents and analytics, which belong to the global family when it exists.

## Choice

- **Inside a component, search is an SDK helper, not a separate service.** The match must sit in the same SQL statement as the data-scope predicate and the cursor; a list answered by another process could show a row the user may not see or skip one they may (the List/Can consistency of [20](20-authorization-provider.md)).
- **A normalised `search_text` column** is written with the row from the fields the component declares: the text itself, its full pinyin and its initials, case- and width-folded. "zgyh" finds 中国银行; pinyin search is required from the first release.
- **One predicate, three speeds.** Every query is `search_text LIKE '%<q>%'`. The SDK probes the database once at start and makes sure the best index exists: a bigram GIN index with `pg_bigm`, a trigram GIN index with `pg_trgm`, or none. Both extensions are optional capabilities, never required ([03-database.md](03-database.md#capability-list)). The rows returned are the same in all three; only the speed differs.
- **Ranking**: a segment equal to `q` (the code, the name, its pinyin or its initials), then a segment that starts with `q`, then any match; ties by the list's own sort.
- **Global search across components is a later slot family**, `infra/search-*`, fed by events and filtered by the caller's access. Nothing is built for it now; its contract shape is reserved below.

**Status**: in place: mdm/customer and mdm/product accept `q` and match it with `strpos(lower(code|name), lower(q))`, ranking prefix matches first; no index serves it, there is no pinyin, and both lists add a 90-day window that the 3.0.0 sweep removes (a full scan once it is gone). Decided (the 3.0.0 sweep and SDK v0.6.0): the column, the normalisation and its vectors, the probe and index management, the ranking, the SQL moving into the SDK. Later: the global search family.

## Port contract

### The column

| Column | Type | Rule |
|---|---|---|
| `search_text` | `TEXT NOT NULL DEFAULT ''` | written by the component in the same statement as the row, on every insert and every update of a source field |
| `search_text_v` | `SMALLINT NOT NULL DEFAULT 0` | the normalisation version that produced the value |

- Pinyin cannot be computed in SQL, so the value is produced in code, not by a trigger.
- **Source fields** are declared by the component per searchable table: typically `code`, `name`, every value of `name_i18n` ([26](26-i18n-data.md#translatable-columns)), and a user-entered mnemonic where the entity has one.
- When the normalisation version rises, a resumable backfill job ([19-background-jobs.md](19-background-jobs.md)) rewrites rows whose `search_text_v` is lower.
- **A personal field makes `search_text` personal**: when a source field is personal data (a contact's phone), the component lists `search_text` among that subject's erasure columns ([09-data-lifecycle.md](09-data-lifecycle.md#erasure)).

### Normalisation, version 1

Applied to each source field, then the segments are joined with `U+001F`, which no user can type:

1. Unicode NFKC (full width to half width, compatibility forms).
2. Lower case (Unicode simple case folding).
3. Segments: the folded text; for text containing Han characters, the full pinyin without tones (`zhongguoyinhang`) and the initials (`zgyh`).
4. A polyphonic character takes the reading the vectors define; each official SDK maps its pinyin library (`go-pinyin`, `pypinyin`, `pinyin-pro`) to that output and carries an override table where the library disagrees.

The query is folded by steps 1 and 2, trimmed, its inner spaces collapsed, control characters removed, and cut at 64 characters. `%`, `_` and `\` are escaped, so they match literally.

The expected outputs go in `vectors/search/` of `be-protocol`, a set that is proposed and not yet written; every SDK's tests will read them.

### The query

```sql
-- $1 = the escaped, normalised q
WHERE <data-scope predicate> AND <list filters>
  AND search_text LIKE '%' || $1 || '%' ESCAPE '\'
ORDER BY CASE
           WHEN position(chr(31) || $1 || chr(31) IN chr(31) || search_text || chr(31)) > 0 THEN 0
           WHEN position(chr(31) || $1 IN chr(31) || search_text) > 0                      THEN 1
           ELSE 2
         END,
         <the list's sort key>, id
```

- Only built-in operators: the query needs no extension on the component's `search_path`.
- With `q`, the cursor encodes the rank, the sort key and the last ID; `q` is part of the filter hash, so a cursor reused with another `q` answers `400 CURSOR_INVALID` ([15](15-user-api-and-errors.md#lists)).
- An empty `q` after normalisation means no search condition.
- Component code never assembles this SQL with string formatting: the SDK produces the fragment and its parameters.

### Index strategy

| Probe in the platform migration (`pg_extension`) | Index the SDK ensures | Fast for |
|---|---|---|
| `pg_bigm` present | `CREATE INDEX CONCURRENTLY IF NOT EXISTS <table>_search_text_idx ON <table> USING gin (search_text <ext schema>.gin_bigm_ops)` | every query, Chinese of two characters included |
| else `pg_trgm` present | the same with `gin_trgm_ops` | queries of three characters or more; shorter ones scan the index |
| neither | none | small tables only |

- The SDK reads the extension's schema from `pg_extension` and qualifies the operator class itself, because component migrations may not contain qualified names. It runs this in the platform migration, logged in as the owner on the dedicated migration connection, because the runtime role has no DDL ([03](03-database.md#roles)); never at run time, never inside a request. The migration step reruns on every `up`, so a newly installed extension is picked up then.
- Extensions are installed once per database by `make db-init`; a component never runs `CREATE EXTENSION`. Both are optional capabilities of the database port ([03-database.md](03-database.md#capability-list)): missing ones slow search down, they never stop a start.
- The chosen strategy is logged once at start.

### Global search (slot family, later)

Reserved so that no component contract has to change when it is built:

- **Members**: `infra/search-pg` (default: PostgreSQL full-text plus bigram index in its own schema), `infra/search-meilisearch`, `infra/search-opensearch`. One family contract, in its own repository like the authz and iam families.
- **Feed**: each owner declares which resource types are globally searchable; the member consumes their events into a projection `{type, id, owner, title, search_text, updated_at, deleted}`. A new member rebuilds it from the owners' `List` backfill, since streams keep only seven days.
- **Query**: `GET /api/search?q=&types=&page_size=&cursor=` through the edge. Candidates are post-filtered with each owner's `_authz/check` (at most 500 per call), fetching more until a page is full. Nothing the caller may not see is ever returned; no exact totals.
- **Addressing**: the shared variable `SEARCH_URL`, filled in `config/vars.yaml` with `$endpoint:<member>` (`$endpoint:infra/search-pg`); absent when no member is installed, and owners and the frontend degrade; no component depends on a member ([0104](../02-decisions/01-architecture/0104-variants-become-slot-families.md), [0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)).

## Alternatives

| Option | Chinese | Operations | Licence | Access filtering | Notes |
|---|---|---|---|---|---|
| **Normalised column + LIKE, index by probe** (chosen) | substrings, pinyin, initials | none new | — | the same SQL | the SDK owns it |
| `strpos` / `LIKE` on raw columns (today) | substrings, no pinyin | none | — | the same SQL | full scans |
| `pg_trgm` alone | three characters and up; two-character queries slow | built-in extension | PostgreSQL | the same SQL | widely available on managed services |
| `pg_bigm` alone | designed for CJK | extension to install | PostgreSQL | the same SQL | availability on managed and Xinchuang databases varies |
| zhparser, pg_jieba (Chinese segmentation for full-text search) | good words, no pinyin | extension with dictionaries | — | the same SQL | Alibaba Cloud RDS offers zhparser |
| ParadeDB `pg_search` (BM25) | depends on the tokenizer | extension | AGPL | the same SQL | licence risk |
| Meilisearch | good, typo tolerant | a separate service | MIT (community) | projected or post-filtered | lightest engine |
| Typesense | fair | a separate service, all in memory | GPL-3.0 | projected or post-filtered | — |
| OpenSearch, Elasticsearch | strong with IK and pinyin plugins | JVM cluster | Apache-2.0; Elastic's licences | projected or post-filtered | large scale |

## Why this choice

- **Access and paging stay correct by construction**: the match, the data scope and the cursor are one statement in the owner's own database.
- **Pinyin is implemented once**, in every SDK from the same vectors, instead of per component.
- **No new infrastructure** on a one-machine deployment, and a database without the extensions still answers correctly.
- **One predicate** makes "the strategies return the same rows" true by construction rather than by testing three code paths.

## Why not the others

- **An external engine for lists**: it needs the access projection copied into it or a post-filter that breaks paging, and it is a second stateful service for every deployment; it cannot serve a component's own `List`.
- **Per-component `LIKE`**: the state today; every component would rewrite folding and pinyin, differently.
- **Segmentation extensions**: dictionaries to maintain, uneven availability, and still no pinyin or initials.
- **`pg_search`**: AGPL.

## When to switch

- **A searchable table passes about a million rows** and measured `q` latency exceeds the route's budget even with the bigram index: start the global family for that type, or add a dedicated index strategy.
- **Search across entities, inside attachments, or with typo tolerance and synonyms** is required: build `infra/search-pg`, then the Meilisearch or OpenSearch member if the measurements ask for it.
- **The database lacks `pg_bigm`** and two-character Chinese queries are slow: install it, or accept the `pg_trgm` behaviour.

## How to switch

- **Index strategy**: install the extension with `make db-init`; at the next `up` the platform migration detects it and builds the index concurrently. No component change.
- **Normalisation**: a new vectors version in be-protocol and an SDK release; the backfill job rewrites rows; components only bump the SDK.
- **Global search**: `brickkit add infra/search-pg`, set `SEARCH_URL: $endpoint:infra/search-pg`, owners declare searchable types. Changing members is `brickkit remove` / `add` and a rebuild of the projection; owners and the frontend do not change.

## Conformance tests

- **Vectors** (proposed): `vectors/search/` in be-protocol (folding, width, pinyin, initials, polyphones, escaping, ranking); every official SDK's tests read them.
- **SDK tests against a real database**, written red first: the three strategies return identical rows for the same data and queries; with `pg_bigm`, `EXPLAIN` shows the index for a two-character Chinese query; `%` and `_` in `q` match literally; a cursor reused with another `q` answers `CURSOR_INVALID`.
- **Components**: mdm/customer and mdm/product, `q=zgyh` finds 中国银行.
- **Measured once** before relying on it: whether `pg_trgm` on `postgres:16-alpine` extracts trigrams from Chinese at all.
- **Global family** (later): suite `tools/be-acceptance/conformance/search/`, per member: an upper bound on indexing delay, invisible records never returned, deleted records disappear, Chinese and pinyin cases.

## Decision records

- [0102 One schema per component](../02-decisions/01-architecture/0102-one-schema-per-component.md): global search reads events, never another schema.
- [0104 Variants become slot families](../02-decisions/01-architecture/0104-variants-become-slot-families.md) and [0107 Family addresses are `$endpoint:` references in shared variables](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md): the search family and `SEARCH_URL`.
- [0206 No row-level security](../02-decisions/02-permissions/0206-no-row-level-security.md): the data scope is a predicate in the same SQL, which is why `q` must be too.
- No new decision is planned; the global family will add its own when it is built.

## Known limits

- **Polyphonic characters** follow one reading per character; a name read differently by its owner may need its mnemonic.
- **No typo tolerance, synonyms or relevance scoring** inside a component; ranking is the three tiers above.
- **Traditional and Simplified Chinese are not folded** yet; this comes as a normalisation version once one mapping produces identical output in every official SDK.
- **Two-character queries with only `pg_trgm`** scan the whole index: correct, slower.
- **`search_text` enlarges every searchable row** by roughly three times its source fields.
- **Global search does not exist**: the top bar's search covers menus only.
