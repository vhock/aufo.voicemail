-- Allow participants to request deletion of their data via the website.
-- We don't actually delete the row here (so operators can audit and follow up),
-- we just flag it with a timestamp. A scheduled job / operator can then purge
-- the personally identifiable fields (email, phone, phone_model).

alter table public.participants
  add column if not exists deletion_requested_at timestamptz;

-- RPC: flag a participant (looked up by phone number) as having requested deletion.
-- Returns:
--   { status: 'flagged',       requested_at: <ts> }  -> first time
--   { status: 'already',       requested_at: <ts> }  -> deletion was already requested earlier
--   { status: 'not_found' }                          -> no participant with that phone number
-- Runs as security definer so it can SELECT/UPDATE without exposing those policies to anon.
create or replace function public.request_participant_deletion(
  p_phone text
)
returns json
language plpgsql
security definer
as $$
declare
  v_existing  timestamptz;
  v_now       timestamptz := now();
  v_found     boolean;
begin
  select deletion_requested_at, true
    into v_existing, v_found
  from public.participants
  where phone = p_phone
  limit 1;

  if not coalesce(v_found, false) then
    return json_build_object('status', 'not_found');
  end if;

  if v_existing is not null then
    return json_build_object('status', 'already', 'requested_at', v_existing);
  end if;

  update public.participants
     set deletion_requested_at = v_now
   where phone = p_phone;

  return json_build_object('status', 'flagged', 'requested_at', v_now);
end;
$$;

grant execute on function public.request_participant_deletion(text) to anon;
