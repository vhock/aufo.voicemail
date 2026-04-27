-- Soft-purge: hard-delete participant rows that were flagged for deletion
-- more than 24h ago. Function is callable by the postgres role (and by
-- pg_cron). Designed to be idempotent and safe to schedule.

create or replace function public.purge_flagged_participants()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
    v_deleted integer;
begin
    delete from public.participants
    where deletion_requested_at is not null
      and deletion_requested_at < (now() - interval '24 hours');
    get diagnostics v_deleted = row_count;
    return v_deleted;
end;
$$;

revoke all on function public.purge_flagged_participants() from public;
revoke all on function public.purge_flagged_participants() from anon, authenticated;

comment on function public.purge_flagged_participants() is
    'Hard-deletes participant rows whose deletion_requested_at is older than 24h. Schedule via pg_cron.';

-- Best-effort: try to enable pg_cron and schedule a daily run. If pg_cron
-- is not available on this Supabase tier, the DO block silently no-ops so
-- the migration still applies cleanly.
do $$
begin
    begin
        create extension if not exists pg_cron;
    exception when others then
        raise notice 'pg_cron extension unavailable: %', sqlerrm;
        return;
    end;

    -- Remove any prior schedule with the same name, then (re)schedule.
    begin
        perform cron.unschedule(jobid)
        from cron.job
        where jobname = 'purge_flagged_participants_daily';
    exception when others then
        -- table missing or permission denied; fall through
        null;
    end;

    begin
        perform cron.schedule(
            'purge_flagged_participants_daily',
            '17 3 * * *',  -- 03:17 UTC every day
            $cron$select public.purge_flagged_participants();$cron$
        );
    exception when others then
        raise notice 'Could not schedule pg_cron job: %', sqlerrm;
    end;
end
$$;
