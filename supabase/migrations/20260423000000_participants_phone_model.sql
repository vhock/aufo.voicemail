-- Add phone_model column so participants don't have to dictate it on every voicemail.
alter table public.participants
  add column if not exists phone_model text;

alter table public.participants
  drop constraint if exists participants_phone_model_length_check,
  add  constraint participants_phone_model_length_check
       check (phone_model is null or char_length(phone_model) between 1 and 128);

-- Recreate the RPC to accept and store the phone model.
create or replace function public.register_or_get_participant(
  p_participant_id text,
  p_email          text,
  p_phone          text,
  p_phone_model    text,
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

  insert into public.participants (participant_id, email, phone, phone_model, ui_language, registered_at)
  values (p_participant_id, p_email, p_phone, p_phone_model, p_ui_language, p_registered_at);

  return json_build_object('status', 'created', 'participant_id', p_participant_id);
end;
$$;

-- Drop the old 5-arg signature so PostgREST doesn't see two overloads.
drop function if exists public.register_or_get_participant(text, text, text, text, timestamptz);

grant execute on function public.register_or_get_participant(text, text, text, text, text, timestamptz) to anon;
