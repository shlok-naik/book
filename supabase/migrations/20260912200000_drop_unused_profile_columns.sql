-- Removes profile schema nothing reads or writes any more.
--
-- `avatar_url` and the public `avatars` bucket backed a membership-card
-- photo that was dropped before it shipped: the card is now flat, with
-- no photo, and no code references either. Both were empty when this
-- was written.
--
-- `name`, `description`, `reading_goal` and `reading_minutes_per_day`
-- were answers an early onboarding questionnaire collected.
-- 20260908000000_drop_onboarding_averages kept them only to avoid
-- throwing away what readers had typed; no row held a value in any of
-- them when this was written, so there is nothing left to protect.
--
-- `profiles` itself stays: `created_at` is the membership card's
-- "member since" date.
drop policy if exists "avatars: public read" on storage.objects;
drop policy if exists "avatars: owner insert" on storage.objects;
drop policy if exists "avatars: owner update" on storage.objects;
drop policy if exists "avatars: owner delete" on storage.objects;

delete from storage.buckets where id = 'avatars';

alter table public.profiles
  drop column if exists avatar_url,
  drop column if exists name,
  drop column if exists description,
  drop column if exists reading_goal,
  drop column if exists reading_minutes_per_day;
