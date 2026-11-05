BEGIN;

CREATE TABLE IF NOT EXISTS public.event_log (
    occurred_at timestamptz NOT NULL,
    id bigint GENERATED ALWAYS AS IDENTITY,
    level varchar(8) NOT NULL CHECK (level IN ('warning', 'error')),
    source varchar(160) NOT NULL,
    code varchar(80) NOT NULL,
    trace_id varchar(80),
    http_method varchar(12),
    route varchar(200),
    status_code smallint CHECK (status_code BETWEEN 400 AND 599),
    exception_type varchar(160),
    fault_site varchar(240),
    sql_state varchar(5),
    PRIMARY KEY (occurred_at, id)
) PARTITION BY RANGE (occurred_at);

CREATE INDEX IF NOT EXISTS event_log_trace_idx ON public.event_log (trace_id, occurred_at DESC, id DESC)
    WHERE trace_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS event_log_level_idx ON public.event_log (level, occurred_at DESC, id DESC);

-- Keep the current and two preceding UTC calendar months. Prepare two months ahead.
CREATE OR REPLACE FUNCTION public.muda_maintain_event_log()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
DECLARE
    current_month timestamp := date_trunc('month', now() AT TIME ZONE 'UTC');
    partition_start timestamp;
    partition_name text;
    oldest_month text := to_char(current_month - interval '2 months', 'YYYYMM');
BEGIN
    IF NOT pg_try_advisory_xact_lock(250025) THEN RETURN; END IF;
    PERFORM set_config('lock_timeout', '2s', true);

    FOR offset_month IN -2..2 LOOP
        partition_start := current_month + make_interval(months => offset_month);
        partition_name := 'event_log_' || to_char(partition_start, 'YYYYMM');
        IF to_regclass('public.' || partition_name) IS NULL THEN
            EXECUTE format('CREATE TABLE public.%I PARTITION OF public.event_log FOR VALUES FROM (%L) TO (%L)',
                partition_name, partition_start AT TIME ZONE 'UTC',
                (partition_start + interval '1 month') AT TIME ZONE 'UTC');
        END IF;
    END LOOP;

    FOR partition_name IN
        SELECT child.relname
        FROM pg_inherits i JOIN pg_class child ON child.oid = i.inhrelid
        JOIN pg_namespace ns ON ns.oid = child.relnamespace
        WHERE i.inhparent = 'public.event_log'::regclass AND ns.nspname = 'public'
          AND child.relname ~ '^event_log_[0-9]{6}$'
          AND right(child.relname, 6) < oldest_month
    LOOP
        EXECUTE format('DROP TABLE public.%I', partition_name);
    END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.muda_maintain_event_log() FROM PUBLIC;
SELECT public.muda_maintain_event_log();

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'damumu_app') THEN
        GRANT SELECT, INSERT ON public.event_log TO damumu_app;
        GRANT EXECUTE ON FUNCTION public.muda_maintain_event_log() TO damumu_app;
    END IF;
END;
$$;

COMMIT;
