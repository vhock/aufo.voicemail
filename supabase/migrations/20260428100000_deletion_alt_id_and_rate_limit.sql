-- Extend deletion request:
--   1. Accept either a phone number or a participant_id (or both) to
--      identify the record. If both are supplied they must point at
--      the same row (otherwise 'not_found' is returned).
--   2. Track per-row deletion_request_count and reject after 5 attempts
--      with status='rate_limited' to limit abuse.

alter table public.participants
    add column if not exists deletion_request_count integer not null default 0;

-- Drop the old single-arg signature; we need the new shape.
drop function if exists public.request_participant_deletion(text);

create or replace function public.request_participant_deletion(
    p_phone          text default null,
    p_participant_id text default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
    v_participant_id text;
    v_existing       timestamptz;
    v_count          integer;
    v_now            timestamptz := now();
    v_phone          text := nullif(btrim(coalesce(p_phone, '')), '');
    v_pid            text := nullif(btrim(coalesce(p_participant_id, '')), '');
begin
    if v_phone is null and v_pid is null then
        return json_build_object('status', 'invalid_input');
    end if;

    select participant_id, deletion_requested_at, deletion_request_count
      into v_participant_id, v_existing, v_count
    from public.participants
    where (v_phone is null or phone = v_phone)
      and (v_pid   is null or participant_id = v_pid)
    limit 1;

    if v_participant_id is null then
        return json_build_object('status', 'not_found');
    end if;

    if coalesce(v_count, 0) >= 5 then
        return json_build_object(
            'status', 'rate_limited',
            'participant_id', v_participant_id
        );
    end if;

    if v_existing is not null then
        update public.participants
           set deletion_request_count = coalesce(deletion_request_count, 0) + 1
         where participant_id = v_participant_id;
        return json_build_object(
            'status', 'already',
            'participant_id', v_participant_id,
            'requested_at', v_existing
        );
    end if;

    update public.participants
       set deletion_requested_at   = v_now,
           deletion_request_count  = coalesce(deletion_request_count, 0) + 1
     where participant_id = v_participant_id;

    return json_build_object(
        'status', 'flagged',
        'participant_id', v_participant_id,
        'requested_at', v_now
    );
end;
$$;

grant execute on function public.request_participant_deletion(text, text) to anon;
