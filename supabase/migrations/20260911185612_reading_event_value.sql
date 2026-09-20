-- Adds a `value` column to `reading_events` — the page number an
-- `update` reached, or the rating a `rate` gave, so the streak/journal
-- page can render "read up to page 240" or "rated 4.5 stars" instead of
-- just naming the command. Nullable and unused by `start`/`finish`/
-- `delete`, which have nothing numeric to say.
alter table public.reading_events
  add column if not exists value numeric;
