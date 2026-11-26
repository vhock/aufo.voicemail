-- Deletion requests via hashed phone number (privacy policy v2).
--
-- The caller number of each voicemail is replaced by a keyed hash when the
-- recordings are processed. The website's deletion form sends the phone
-- number to request_recording_deletion(), which hashes it immediately and
-- stores only the hash. The processing pipeline deletes recordings whose
-- caller hash matches an open request, then sets processed_at.
--
-- Hash: lower-case hex of HMAC-SHA256(<E.164 number, e.g. +491711234567>, key).
-- A keyed hash is required: phone numbers have so little entropy that a plain
-- SHA-256 could be reversed by hashing every possible number.
--
-- PREREQUISITE (run once, manually; never commit the key):
--     select vault.create_secret('<output of: openssl rand -hex 32>', 'phone_hash_key');
-- The pipeline must hash caller numbers with the same key, either locally or
-- by calling public.phone_hash() with the service-role key.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.deletion_requests (
    phone_hash     text primary key,
    requested_at   timestamptz not null default now(),
    request_count  integer not null default 1,
    processed_at   timestamptz
);

comment on table public.deletion_requests is
    'Open/processed deletion requests, keyed by HMAC-SHA256 of the caller number. Never contains the number itself.';
comment on column public.deletion_requests.processed_at is
    'Set by the processing pipeline once all recordings with this caller hash have been deleted.';

alter table public.deletion_requests
    drop constraint if exists deletion_requests_phone_hash_check,
    add  constraint deletion_requests_phone_hash_check
         check (phone_hash ~ '^[0-9a-f]{64}$');

-- RLS on, no policies: anon/authenticated cannot touch the table directly.
alter table public.deletion_requests enable row level security;
revoke all on table public.deletion_requests from anon, authenticated;

-- Keyed hash of an E.164 phone number. Not callable by anon.
create or replace function public.phone_hash(p_phone text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_key text;
begin
    select decrypted_secret into v_key
    from vault.decrypted_secrets
    where name = 'phone_hash_key'
    limit 1;

    if v_key is null then
        raise exception 'vault secret "phone_hash_key" is missing';
    end if;

    return encode(extensions.hmac(btrim(p_phone), v_key, 'sha256'), 'hex');
end;
$$;

revoke all on function public.phone_hash(text) from public;
revoke all on function public.phone_hash(text) from anon, authenticated;
grant execute on function public.phone_hash(text) to service_role;

-- Called by the website. Returns { status: 'recorded' | 'already' | 'invalid_input' }.
create or replace function public.request_recording_deletion(p_phone text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_phone     text := btrim(coalesce(p_phone, ''));
    v_hash      text;
    v_processed timestamptz;
begin
    if v_phone !~ '^\+[1-9][0-9]{7,14}$' then
        return json_build_object('status', 'invalid_input');
    end if;

    v_hash := public.phone_hash(v_phone);

    insert into public.deletion_requests (phone_hash)
    values (v_hash)
    on conflict (phone_hash) do nothing;

    if found then
        return json_build_object('status', 'recorded');
    end if;

    select processed_at into v_processed
    from public.deletion_requests
    where phone_hash = v_hash
    for update;

    if v_processed is not null then
        -- Earlier request was already carried out; re-open it so recordings
        -- made since then are deleted as well.
        update public.deletion_requests
           set requested_at  = now(),
               processed_at  = null,
               request_count = request_count + 1
         where phone_hash = v_hash;
        return json_build_object('status', 'recorded');
    end if;

    update public.deletion_requests
       set request_count = request_count + 1
     where phone_hash = v_hash;
    return json_build_object('status', 'already');
end;
$$;

revoke all on function public.request_recording_deletion(text) from public;
grant execute on function public.request_recording_deletion(text) to anon;
