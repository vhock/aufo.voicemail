-- Remove test rows inserted during initial connection check
delete from public.feedback where participant_id = 'TEST';

-- Hard limits to discourage abuse since anon can insert
alter table public.feedback
  drop constraint if exists feedback_ease_rating_check,
  add  constraint feedback_ease_rating_check
       check (ease_rating is null or (ease_rating between 1 and 5));

alter table public.feedback
  drop constraint if exists feedback_text_length_check,
  add  constraint feedback_text_length_check
       check (char_length(coalesce(feedback_text, '')) <= 4000);

alter table public.feedback
  drop constraint if exists feedback_participant_id_length_check,
  add  constraint feedback_participant_id_length_check
       check (participant_id is null or char_length(participant_id) <= 64);

alter table public.feedback
  drop constraint if exists feedback_voicemail_language_check,
  add  constraint feedback_voicemail_language_check
       check (voicemail_language is null or char_length(voicemail_language) <= 32);

alter table public.feedback
  drop constraint if exists feedback_ui_language_check,
  add  constraint feedback_ui_language_check
       check (ui_language is null or char_length(ui_language) <= 8);
