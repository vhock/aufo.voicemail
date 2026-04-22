-- Remove the connection-test row inserted while wiring up the participants table
delete from public.participants where participant_id = 'TEST';
