-- profiles.display_name — the reader's name, asked for first in onboarding.
--
-- It used to live only on the device, so it didn't follow the reader to a
-- new phone or through an email link. The `profiles: update own` policy
-- already lets a reader write their own row, so no policy changes.

alter table public.profiles
  add column if not exists display_name text
    check (
      display_name is null
      or char_length(btrim(display_name)) between 1 and 40
    );
