-- A candidate for be_analyze_stale(): the same decision from the statistics functions by oid, without the
-- pg_stat_all_tables view (built in the measuring schema only, by bench-stale.sh).
CREATE OR REPLACE FUNCTION idle.be_analyze_stale_byoid() RETURNS SETOF text LANGUAGE plpgsql SECURITY DEFINER AS $body$
DECLARE
    t        text;
    rel      oid;
BEGIN
    IF NOT pg_try_advisory_xact_lock(hashtextextended('be_analyze:' || current_schema(), 0)) THEN
        RETURN;
    END IF;
    FOREACH t IN ARRAY ARRAY['be_outbox', 'be_work_item', 'be_audit_log'] LOOP
        rel := format('%I.%I', current_schema(), t)::regclass;
        IF pg_stat_get_mod_since_analyze(rel) >= greatest(1000, (SELECT reltuples FROM pg_class WHERE oid = rel))
            AND coalesce(greatest(pg_stat_get_last_analyze_time(rel), pg_stat_get_last_autoanalyze_time(rel)) < now() - interval '30 seconds', true) THEN
            EXECUTE format('ANALYZE (SKIP_LOCKED) %I.%I', current_schema(), t);
            RETURN NEXT t;
        END IF;
    END LOOP;
END
$body$;
ALTER FUNCTION idle.be_analyze_stale_byoid() SET search_path = idle, pg_temp;
