-- The Goodreads import as a baseline for stats.
--
-- Imported books are history, not reading done in cactus: they must not
-- count toward the stats page's books-per-month and pages-per-month
-- charts, and the pace chart starts from the moment of the import, with
-- what was already finished that year as its baseline.
--
-- * `user_books.imported` — true for every row a Goodreads import created.
--   Books added afterwards keep the default false.
-- * `profiles.library_imported_at` — when the last import happened; the
--   pace chart's baseline date.
-- * `mark_library_imported()` — stamps both, called by the app right after
--   `replace_library` succeeds. `replace_library` wipes the library first,
--   so every row that exists at that moment came from the import.
--   `security invoker`: RLS limits both updates to the caller's own rows.
--   Returns the stamp, from the server clock (the same clock `finished_at`
--   comparisons are made against, never the device's).

alter table public.user_books
  add column if not exists imported boolean not null default false;

alter table public.profiles
  add column if not exists library_imported_at timestamptz;

create or replace function public.mark_library_imported()
returns timestamptz
language plpgsql
security invoker
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  stamp  timestamptz := now();
begin
  if caller is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  update public.user_books set imported = true where user_id = caller;
  update public.profiles set library_imported_at = stamp where id = caller;

  return stamp;
end;
$$;

revoke execute on function public.mark_library_imported() from public, anon;
grant execute on function public.mark_library_imported() to authenticated;
