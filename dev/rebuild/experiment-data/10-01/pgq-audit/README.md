# B2 smoke (2026-10-28 06:43-07:07): the PostgreSQL queue cells record 16 more audit records

D9-S-pgq and D9-X-pgq (bus: pgqueue), short parameters: every digest item equal to D8-S's except
`infra_audit.audit_record.count`, 112265 against 112249 (`*-compare.log`: reference != this cell).

`*-before-load.tsv`: the cell's audit records written before its load (occurred_at before the chain stage), grouped
by actor (`user` for a person, else the component's system identity), operation and outcome; the query:

    select case when r->>'actor' ~ '^[0-9a-f]{8}-' then 'user' else r->>'actor' end, r->>'operation', r->>'outcome', count(*)
    from (select convert_from(record,'UTF8')::jsonb r from infra_audit.audit_record) x
    where (r->>'occurred_at')::timestamptz < '<chain stage start, UTC>' group by 1,2,3 order by 1,2,3

(D9-S-pgq's file keeps the person's principal instead of `user` and a category column.) Explained (step10-plan 5.2): the
currency seed writes 16 rates per weekday of the last 60 days; 10-28 has 43 weekdays in that window, the day D8-S's
reference was made (10-25) 42. D9-S (JetStream) in the B1+B2 batch has the same 112265.

D9-S-before-load.tsv: the JetStream cell of the B1+B2 batch, taken in its warmup (not a measured window); line for
line the same as D9-X-pgq-before-load.tsv. exchange_rate.maintain 698 = 43 weekdays x 16 + 9 budget rates + 1 correction.
