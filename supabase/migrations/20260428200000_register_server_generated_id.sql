-- Server-generated participant IDs with retry on PK collision.
--
-- Previously the website passed a random 4-digit string and inserted it
-- as the primary key. With only 9000 possible IDs the birthday paradox
-- gives a ~50% collision probability at ~95 participants, causing the
-- INSERT to fail with a PK violation. This migration moves ID generation
-- into the database and retries on collision.
--
-- The function keeps the existing return contract:
--     { status: 'created'|'existing', participant_id: text }
-- so the frontend continues to work even if it still sends p_participant_id
-- (the value is ignored).

drop function if exists public.register_or_get_participant(
    text, text, text, text, text, timestamptz
);
drop function if exists public.register_or_get_participant(
    text, text, text, text, timestamptz
);
drop function if exists public.register_or_get_participant(
    text, text, text, timestamptz
);

create or replace function public.register_or_get_participant(
    p_email         text,
    p_phone         text,
    p_phone_model   text,
    p_ui_language   text,
    p_registered_at timestamptz default now(),
    p_participant_id text default null  -- accepted for backwards compat, ignored
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
    -- Existing registration for this phone? Return its ID.
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
    -- Format: P-XXXXXX (6 base36 chars) -> ~2.18 billion possibilities.
    loop
        v_attempt := v_attempt + 1;
        v_new_id := 'P-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));

        begin
            insert into public.participants (
                participant_id, email, phone, phone_model, ui_language, registered_at
            ) values (
                v_new_id, p_email, p_phone, p_phone_model, p_ui_language, p_registered_at
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
                -- Another race may have inserted this exact phone in between
                -- our SELECT and INSERT. Re-check before retrying ID.
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
    text, text, text, text, timestamptz, text
) to anon;
