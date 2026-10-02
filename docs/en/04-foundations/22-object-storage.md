[English](22-object-storage.md) · [中文](../../zh/04-foundations/22-object-storage.md)

# Object storage

Where files and large results live: the S3 API as the port, one bucket and one credential per component, what every official SDK's blob client does on the wire, presigned uploads and downloads, attachments with their authorization and virus scanning, retention and Object Lock, large results handed over by reference, and where frozen data sits. For whoever stores a file, returns a PDF, adds attachments to a document, or is asked to support another storage product.

## Scope

- **In:** configuration keys; buckets, credentials and policies; the key layout inside a bucket; the blob client's operations; presigned URLs; the attachment component; scanning; lifecycle rules and Object Lock; the claim check for large results; the place of the cold store in a bucket.
- **Out:** the data lifecycle engine, its tiers, the Parquet format and manifest, the `ColdStore` and `ColdQuery` adapters ([09-data-lifecycle.md](09-data-lifecycle.md)); secret delivery and rotation ([24-config-and-secrets.md](24-config-and-secrets.md)); the browser's route to the store ([18-edge.md](18-edge.md#object-storage-through-the-edge)); backup of the store (the operations documents, planned).

## Choice

- **The S3 API is the port** ([0106](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)). RustFS is the default server; MinIO, AWS S3, Alibaba Cloud OSS and other S3-compatible stores are swapped by configuration. Product-specific keys (`MINIO_*`, `RUSTFS_*`) are never read.
- **One bucket and one credential per component**, with a policy that reaches only that bucket: the object-storage form of one schema and one role per component ([0102](../02-decisions/01-architecture/0102-one-schema-per-component.md)). be-ops generates `make storage-init` beside `make db-init`.
- **Every official SDK has a blob client** with the same operations and rules (protocol P17), backed by each language's S3 library (`aws-sdk-go-v2` in Go, `aioboto3` in Python).
- **Files never travel in a component's request or response body.** Browsers upload and download with presigned URLs valid at most 5 minutes; a bucket is never publicly readable.
- **`infra/attachment` owns attachments**: metadata, authorization through the parent record, upload into quarantine, scanning, release.
- **Scanning is an adapter**: ClamAV through `SCAN_URL`, or none. On in production, off in development by default.
- **Retention by lifecycle rules**; legal archives by Object Lock in compliance mode; data that may have to be erased is never locked.
- **Large results by reference** (claim check): an object key and a checksum, never the bytes, in a gRPC answer or an event.

**Status**: in place: the shared key `S3_URL` and the RustFS container (MinIO as a mutually exclusive profile); no component uses object storage, components hold no storage credentials, and infra/print returns PDF bytes inside a gRPC response, which fails above the 4 MiB message limit. Decided (lands with the 3.0.0 sweep and SDK v0.6.0): the keys, a bucket and a credential per component, `make storage-init`, the blob client, the presigning rules, the `blob` suite, print's object-based rendering. Later: `infra/attachment` and scanning (registered, port 8204, schema `infra_attachment`, not built), built when the first document needs attachments; the cold store's `s3-parquet` adapter follows the data lifecycle phases ([09](09-data-lifecycle.md)).

## Port contract

### Configuration keys

| Key | Shared | Default | Meaning |
|---|---|---|---|
| `S3_URL` | yes, `$var:S3_URL` | — | the store's API address inside the project network |
| `S3_PUBLIC_URL` | yes | `S3_URL` | the address browsers use; presigned URLs are signed for it |
| `S3_REGION` | yes | `us-east-1` | the signing region |
| `S3_FORCE_PATH_STYLE` | yes | `false` | `true` for RustFS and MinIO |
| `S3_BUCKET` | no | — (required; the deployment writes the registry's bucket name) | this component's bucket |
| `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | no, secret (`${…}`) | — | this component's own credential |
| `SCAN_URL` | yes (attachment only) | absent = no scanning | the scanner, `clamd://<host>:3310` |

A component uses object storage exactly when its `configSchema` declares `S3_BUCKET`; that also turns on the `blob` profile of the component protocol suite. Every key here except `SCAN_URL` is a protocol key (`be-protocol` `schemas/config-keys.yaml`, P17).

### Buckets, credentials, policies

- `registry/schemas.tsv` gains an append-only `bucket` column. The default name is the registry ID (`erp-finance`, `infra-attachment`), because S3 names allow no underscore. Where bucket names are global (AWS S3, OSS), the deployment writes a prefixed name into the component's `S3_BUCKET`.
- The policy allows `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket`, `s3:AbortMultipartUpload`, `s3:ListMultipartUploadParts` on its own bucket and its objects, plus `s3:PutObjectRetention` and `s3:PutObjectLegalHold` where Object Lock is on. Nothing else: no bucket creation, no policy changes, no other bucket.
- `make storage-init` is idempotent: it creates each bucket, blocks public access, creates the component's user and access key, attaches the policy, installs the lifecycle rules below, and enables Object Lock (with the versioning it requires) only for components whose lifecycle declaration needs it. Generated credentials go where `config/` references them as secrets, never into a tracked file.
- In a shell every member keeps its own credential and its own client ([27-shells.md](27-shells.md)).

### Key layout

| Prefix | Written by | Lifecycle rule | Notes |
|---|---|---|---|
| `quarantine/<id>` | attachment uploads | expire after 24 h | never downloadable |
| `clean/<id>` | attachment, after the scan | none; removed with the attachment | |
| `tmp/` | any component: rendered files, claim-check results | expire after 24 h | |
| `exports/<job>/` | the lifecycle engine's asynchronous exports | removed when the export expires | |
| `cold/<table>/v<n>/unit=<YYYY-MM>/tenant=<t>/part-NNNN.parquet`, `cold/<table>/_manifests/<unit>.json` | the lifecycle engine | none; the engine decides | cold data lives in the component's own bucket; format and manifest in [09](09-data-lifecycle.md#the-cold-format) |
| `_erasures/` | the lifecycle engine | none; append-only | replays erasures after a point-in-time restore |

Every bucket also aborts incomplete multipart uploads after 24 h. Object keys never contain personal data or file names: keys appear in logs and URLs; a file name lives in metadata and in `Content-Disposition`.

### The blob client

The same operations in every official SDK; each call carries the caller's remaining deadline ([16](16-deadlines-and-retries.md)).

| Operation | S3 request | Rules |
|---|---|---|
| put | `PutObject`, multipart above the SDK's part size | `Content-Type` always set |
| get | `GetObject` with optional `Range` | streams; never buffers a whole object |
| head | `HeadObject` | size, type, checksum |
| delete | `DeleteObject` | idempotent |
| list | `ListObjectsV2` by prefix | for the lifecycle engine and reconcilers |
| presign put | presigned `PutObject` | see below |
| presign get | presigned `GetObject` | see below |

Errors: `NoSuchKey` → `NOT_FOUND`; `AccessDenied` → `INTERNAL` (a configuration error, logged with the bucket, never shown); `SlowDown` and 5xx → retried with backoff within the deadline, then `UNAVAILABLE`.

### Presigned URLs

- Issued only after the caller's authorization was checked; valid at most 300 s; signed for `S3_PUBLIC_URL`. A full URL is never logged: the signature is redacted.
- **Upload**: a presigned `PUT` signs `Content-Type` and the exact `Content-Length` the client declared, so the store refuses any other size. S3 cannot cap a presigned `PUT` by a range; a browser form upload uses a presigned `POST` whose policy carries `content-length-range`.
- **Download**: a presigned `GET` with `response-content-disposition: attachment; filename*=UTF-8''<encoded name>` and `response-content-type`; `inline` only for an allow-list of safe types (PDF, raster images).
- The browser reaches the store through its own host name at the edge ([18](18-edge.md#object-storage-through-the-edge)).

### Attachments (`infra/attachment`, later)

Metadata, one row per file: `id` (UUIDv7), `owner_component`, `resource_type`, `resource_id` (text), `filename`, `content_type`, `size_bytes`, `sha256`, `state` (`PENDING_UPLOAD`, `SCANNING`, `READY`, `REJECTED`, `DELETED`), `scan_result`, `legal_hold`, `created_by`, `created_at`.

| Endpoint | Does |
|---|---|
| `POST /infra/attachment/uploads` `{resource_type, resource_id, filename, content_type, size, sha256, idempotency_key}` | checks the parent through its owner's `POST {prefix}/_authz/check` with the key the owner declares for attaching; answers `{attachment_id, upload: {method, url, headers, expires_at}}` into `quarantine/` |
| `POST /infra/attachment/attachments/{id}:complete` | heads the object, compares size and checksum, starts the scan |
| `GET /infra/attachment/attachments?resource_type=&resource_id=` | checks the parent once, lists its attachments |
| `GET /infra/attachment/attachments/{id}/download` | `{url, expires_at}`, only when `READY` |
| `DELETE /infra/attachment/attachments/{id}` | marks `DELETED`; the object goes unless a legal hold is set |

- An invisible parent answers 404 for every endpoint ([15](15-user-api-and-errors.md#status-codes-for-access)); listing "all attachments I may see" across parents is not offered ([20](20-authorization-provider.md#port-contract)).
- Events `infra.attachment.attachment.ready.v1`, `.rejected.v1`, `.deleted.v1`, aggregate type `infra.attachment.attachment`.
- The attachment component reaches each owner's resource contract over the user plane with the user's token, declaring the owners as optional dependencies, as every aggregating component does ([02-backend.md](../01-conventions/02-backend.md#calling-other-components)).

### Scanning

- `SCAN_URL` selects the adapter by scheme: `clamd://` streams the object to ClamAV (`INSTREAM`); absent means `none`: files become `READY` with `scan_result: SKIPPED`, and the component warns once at start.
- Clean: copy `quarantine/<id>` to `clean/<id>`, delete the original, `READY`, publish the event. Infected, too large for the scanner, or a scanner error after retries: `REJECTED`, never released unscanned.
- ClamAV is infrastructure (its official image plus configuration, [0106](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)), GPL-licensed but used as a separate process.

### Retention and Object Lock

- Lifecycle rules handle the short-lived prefixes above.
- **Object Lock, compliance mode**, with a retain-until date per object, never a bucket default: for frozen ledger units and electronic accounting archives, whose tables carry no personal data. A legal hold uses the store's object legal hold where Object Lock is on, and the `legal_hold` flag otherwise.
- **Never lock what may be erased**: erasable tables are frozen without retention, so their objects can be rewritten ([09](09-data-lifecycle.md#erasure)). Together with "ledger tables hold no personal data", "cannot be altered" and "can be erased" always fall on different objects.
- Encryption at rest is the store's own setting, not part of this contract.

### Large results

- **Rendering**: infra/print gains `RenderToObject` (an addition to its contract): the file goes to print's bucket under `tmp/`, the answer carries an attachment ID or a presigned `GET`. The existing rpc stays, with its 4 MiB limit written into the contract.
- **Events above 64 KiB** ([13-event-contracts.md](13-event-contracts.md)) carry `{key, sha256, size}` of an object in the producer's bucket. A consumer never holds the producer's credential: it obtains a short-lived presigned URL through an rpc the producer declares for that purpose.

## Alternatives

How files are stored:

| | S3 API, a bucket and a credential per component (chosen) | Files in PostgreSQL (`bytea`, large objects) | One shared bucket, a prefix per component | Uploads through the component | A shared file system (NFS, a volume) |
|---|---|---|---|---|---|
| Isolation | policy per bucket | schema per component | one key reads everything | as chosen | none |
| Large files | direct, multipart | swell backups and replication | direct | pass through the process | direct |
| Portability | every cloud and on-premise store | the database | every store | — | per host |
| Retention, WORM | lifecycle rules, Object Lock | by hand | rules per prefix | — | none |

Which server (all behind the same port):

| Server | Licence | Fits | Watch |
|---|---|---|---|
| RustFS (default) | Apache-2.0 | one machine, small clusters | young; IAM policies and Object Lock to be measured |
| MinIO | AGPL-3.0 | known behaviour, mature IAM | the community edition was cut back from 2025; licence terms |
| Ceph RGW | LGPL | customers already running Ceph | heavy for one machine |
| SeaweedFS | Apache-2.0 | many small files | S3 coverage to be measured |
| AWS S3, Alibaba Cloud OSS, Tencent Cloud COS | managed | customers on that cloud | global bucket names; OSS in its S3-compatible mode |

## Why this choice

- **One isolation model everywhere**: a component reads and writes only its own schema in the database and its own bucket in the store, with its own credential.
- **Large files never pass through a component**, so neither memory nor the 1 MiB body limit nor the 4 MiB gRPC limit is in the way, and a shell's members are not slowed by one member's upload.
- **The S3 API is what every store speaks**, so a customer's existing storage is a configuration value.
- **Authorization stays with the record that owns the file**: an attachment is as visible as its parent, decided by the parent's owner.

## Why not the others

- **`bytea` or large objects**: every file enters backups, replication and point-in-time recovery; the database is the most expensive place to keep bytes.
- **A shared bucket with prefixes**: one leaked credential reads every component's files; per-prefix policies are possible but nothing checks them per component.
- **Uploads through the component**: each upload holds a connection and memory in a process that also serves requests, and needs a body limit no other route wants.
- **A shared file system**: no presigned access, no retention rules, nothing on Kubernetes without a storage class.
- **A product SDK** (MinIO's, OSS's): ties the code to one product, against 0106.

## When to switch

- **A customer's infrastructure**: their store, by configuration.
- **RustFS fails a measured requirement** (policies, Object Lock, multipart): MinIO or another server that passes the `blob` suite.
- **Antivirus is mandated with a product other than ClamAV**: a new scanner adapter behind `SCAN_URL`.
- **Cross-component reads of files become common**: revisit the claim check, not the credential rule.

## How to switch

1. Start the new store; set `S3_URL`, `S3_PUBLIC_URL`, `S3_REGION`, `S3_FORCE_PATH_STYLE` in `config/vars.yaml`.
2. Run `make storage-init` against it; put the new credentials where `config/` references them.
3. Copy the objects (`rclone sync`, or the store's mirror tool), bucket by bucket.
4. Run the `blob` suite against the new store; restart the components. No component code, contract or pin changes.

The scanner: set or remove `SCAN_URL`; nothing else.

## Conformance tests

Planned suite `tools/be-acceptance/conformance/blob/`, run against RustFS, MinIO, AWS S3 and OSS:

- a presigned `PUT` refuses a body of another length; a presigned `POST` refuses one outside its range;
- a presigned `GET` answers 403 after expiry; `Range` reads return the right bytes; multipart uploads complete and abort;
- a component's credential cannot list, read or write another component's bucket; anonymous reads are refused;
- lifecycle rules expire `quarantine/` and `tmp/`;
- with Object Lock in compliance mode, deleting before the retain-until date fails.

Component profile `blob` of the component protocol suite (`tools/be-acceptance/conformance/component/`): presigned uploads carry a length limit; the bucket is not anonymously readable; presigned URLs live at most 5 minutes.

Tests written red first: be-sdk-go "a presigned upload above the declared size is refused", "a presigned download answers 403 after expiry", "a credential cannot reach another component's bucket"; be-ops "storage-init creates each bucket and policy, idempotently"; infra/print "a result above 4 MiB goes through `RenderToObject`"; attachment, when built: "not downloadable before the scan", "an invisible parent answers 404".

## Decision records

- [0106 Infrastructure is not a component](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md): the S3 API is the port; the store and the scanner are infrastructure.
- [0102 One schema per component](../02-decisions/01-architecture/0102-one-schema-per-component.md): the isolation model this document extends to buckets.
- [0302 Contracts change by adding only](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md): `RenderToObject` beside the existing rpc.
- [0212 A record the caller cannot see answers 404](../02-decisions/02-permissions/0212-invisible-records-answer-404.md): an attachment of an invisible parent answers 404.
- Planned, not yet numbered: "one bucket and one credential per component".

## Known limits

- **RustFS's IAM policies and Object Lock are not yet measured**; until the `blob` suite passes, Object Lock is promised only on stores that pass it.
- **A presigned URL works for whoever holds it** until it expires (at most 5 minutes).
- **The browser needs a route to the store** under its own host name; a store reachable only inside the project network cannot serve presigned URLs.
- **A new owner of attachments** needs an attachment release to add it as an optional dependency.
- **Retention follows the parent only through events**: an attachment outlives a destroyed parent until the event is processed.
- **Attachments and scanning are not built**; until then no component accepts files.
