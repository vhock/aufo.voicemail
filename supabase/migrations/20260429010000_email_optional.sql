-- Email is now optional on the registration form (DSGVO data minimisation).
-- Allow NULL in participants.email so the new RPC can insert without one.

alter table public.participants
    alter column email drop not null;

comment on column public.participants.email is
    'Optional contact email. May be NULL when participant declined to provide one.';
