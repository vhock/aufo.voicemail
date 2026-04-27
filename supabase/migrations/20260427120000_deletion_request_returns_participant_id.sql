-- Extend the deletion-request RPC so the response also includes the
-- participant_id of the affected row. This lets the website confirm
-- to the user which record was flagged.

create or replace function public.request_participant_deletion(
  p_phone text
)
returns json
language plpgsql
security definer
as $$
declare
  v_participant_id text;
  v_existing       timestamptz;
  v_now            timestamptz := now();
begin
  select participant_id, deletion_requested_at
    into v_participant_id, v_existing
  from public.participants
  where phone = p_phone
  limit 1;

  if v_participant_id is null then
    return json_build_object('status', 'not_found');
  end if;

  if v_existing is not null then
    return json_build_object(
      'status', 'already',
      'participant_id', v_participant_id,
      'requested_at', v_existing
    );
  end if;

  update public.participants
     set deletion_requested_at = v_now
   where phone = p_phone;

  return json_build_object(
    'status', 'flagged',
    'participant_id', v_participant_id,
    'requested_at', v_now
  );
end;
$$;

grant execute on function public.request_participant_deletion(text) to anon;
