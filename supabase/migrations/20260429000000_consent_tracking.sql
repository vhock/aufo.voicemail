-- Migration: track GDPR consent (Art. 7 (1) GDPR — proof of consent)
--
-- Adds consent_version + consented_at columns to participants and
-- extends register_or_get_participant() with a p_consent_version
-- parameter. The previous signature is dropped and replaced.

alter table public.participants
    add column if not exists consent_version text,
    add column if not exists consented_at    timestamptz;

comment on column public.participants.consent_version is
    'Version identifier of the privacy policy / consent text the participant agreed to (e.g. v1-2026-04-27).';
comment on column public.participants.consented_at is
    'Server-side timestamp at which the participant''s consent was recorded (Art. 7 (1) GDPR proof of consent).';

-- Drop the previous signature (text,text,text,text,timestamptz,text).
drop function if exists public.register_or_get_participant(
    text, text, text, text, timestamptz, text
);

create or replace function public.register_or_get_participant(
    p_email           text,
    p_phone           text,
    p_phone_model     text,
    p_ui_language     text,
    p_registered_at   timestamptz default now(),
    p_consent_version text default null,
    p_participant_id  text default null  -- accepted for backwards compat, ignored
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
    v_existing_id text;
    v_new_id      text;
    v_attempt     int := 0;
begin
    if p_phone is null or btrim(p_phone) = '' then
        raise exception 'phone is required';
    end if;
    if p_phone_model is null or btrim(p_phone_model) = '' then
        raise exception 'phone_model is required';
    end if;
    if p_consent_version is null or btrim(p_consent_version) = '' then
        raise exception 'consent_version is required (GDPR Art. 7 (1))';
    end if;

    -- Existing registration for this phone? Return its ID without
    -- overwriting the original consent record.
    select participant_id
      into v_existing_id
    from public.participants
    where phone = p_phone
    limit 1;

    if v_existing_id is not null then
        return json_build_object(
            'status', 'existing',
            'participant_id', v_existing_id
        );
    end if;

    -- Generate a fresh random ID; retry up to 20 times on the rare collision.
    loop
        v_attempt := v_attempt + 1;
        v_new_id := 'P-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));

        begin
            insert into public.participants (
                participant_id, email, phone, phone_model, ui_language,
                registered_at, consent_version, consented_at
            ) values (
                v_new_id,
                nullif(btrim(coalesce(p_email, '')), ''),
                p_phone,
                p_phone_model,
                p_ui_language,
                p_registered_at,
                btrim(p_consent_version),
                now()
            );
            return json_build_object(
                'status', 'created',
                'participant_id', v_new_id
            );
        exception
            when unique_violation then
                if v_attempt >= 20 then
                    raise;
                end if;
                -- Race: another tx may have inserted the same phone.
                select participant_id
                  into v_existing_id
                from public.participants
                where phone = p_phone
                limit 1;
                if v_existing_id is not null then
                    return json_build_object(
                        'status', 'existing',
                        'participant_id', v_existing_id
                    );
                end if;
                -- otherwise loop and try a fresh ID
        end;
    end loop;
end;
$$;

grant execute on function public.register_or_get_participant(
    text, text, text, text, timestamptz, text, text
) to anon, authenticated;
