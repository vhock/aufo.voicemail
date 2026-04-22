-- Unique constraint so the same phone can't register twice
alter table public.participants
  drop constraint if exists participants_phone_unique,
  add  constraint participants_phone_unique unique (phone);

-- RPC: atomically insert a new participant OR return the existing one for a phone number.
-- Runs as security definer (postgres) so it can SELECT without exposing a SELECT RLS policy.
create or replace function public.register_or_get_participant(
  p_participant_id text,
  p_email          text,
  p_phone          text,
  p_ui_language    text,
  p_registered_at  timestamptz
)
returns json
language plpgsql
security definer
as $$
declare
  existing_id text;
begin
  select participant_id into existing_id
  from public.participants
  where phone = p_phone
  limit 1;

  if existing_id is not null then
    return json_build_object('status', 'existing', 'participant_id', existing_id);
  end if;

  insert into public.participants (participant_id, email, phone, ui_language, registered_at)
  values (p_participant_id, p_email, p_phone, p_ui_language, p_registered_at);

  return json_build_object('status', 'created', 'participant_id', p_participant_id);
end;
$$;

-- Allow anonymous callers (the browser) to invoke the function
grant execute on function public.register_or_get_participant to anon;
