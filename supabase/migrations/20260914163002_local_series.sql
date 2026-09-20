-- Series become private to each reader, like `shelves` and `tags` — not
-- shared across readers the way `book_series` + `reader_series` had them.
-- A book's series membership moves from the shared `books` row
-- (`series_id`/`series_position`) onto the reader's own `user_books` row,
-- the same place `shelf_id` already lives.
--
-- `make_book_series`/`set_book_series` are dropped along with them: with
-- nothing shared left to negotiate (no "first writer wins", no joining a
-- name another reader already picked), making and applying a series is a
-- plain insert/update under RLS, exactly like a shelf.
--
-- Sections:
--   1. series (private, mirrors `shelves`)
--   2. user_books.series_id / series_position (+ backfill from book_series)
--   3. drop the shared book_series / reader_series machinery
--   4. adopt_library — carries the new `series` table along

-- ==================================================================== 1. series
create table if not exists public.series (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 80),
  created_at timestamptz not null default now(),
  unique (user_id, id)
);

create unique index if not exists series_name_per_reader
  on public.series (user_id, lower(regexp_replace(btrim(name), '\s+', ' ', 'g')));

alter table public.series enable row level security;

drop policy if exists "series: select own" on public.series;
create policy "series: select own"
  on public.series for select to authenticated
  using ((select auth.uid()) = user_id);
drop policy if exists "series: insert own" on public.series;
create policy "series: insert own"
  on public.series for insert to authenticated
  with check ((select auth.uid()) = user_id);

-- ============================================== 2. user_books.series_id/position
alter table public.user_books
  add column if not exists series_id uuid;
alter table public.user_books
  add column if not exists series_position numeric;

alter table public.user_books
  drop constraint if exists user_books_series_fkey;
alter table public.user_books
  add constraint user_books_series_fkey
    foreign key (user_id, series_id) references public.series (user_id, id)
    on update cascade
    on delete set null (series_id);

create index if not exists user_books_series_id_idx
  on public.user_books (user_id, series_id)
  where series_id is not null;

-- Every reader who had a book filed in a shared series gets their own
-- private series of the same name, and their `user_books` row is filed
-- under it at the same position. Best-effort: this only ever ran against
-- pre-launch data.
insert into public.series (user_id, name)
select distinct ub.user_id, bs.name
from public.user_books ub
join public.books b on b.id = ub.book_id
join public.book_series bs on bs.id = b.series_id
where b.series_id is not null
on conflict do nothing;

update public.user_books ub
   set series_id = s.id,
       series_position = b.series_position
  from public.books b
  join public.book_series bs on bs.id = b.series_id
  join public.series s
    on lower(regexp_replace(btrim(s.name), '\s+', ' ', 'g'))
       = lower(regexp_replace(btrim(bs.name), '\s+', ' ', 'g'))
 where ub.book_id = b.id
   and b.series_id is not null
   and s.user_id = ub.user_id;

-- ========================================== 3. drop the shared series tables
drop function if exists public.set_book_series(uuid, text, numeric);
drop function if exists public.make_book_series(text);

drop table if exists public.reader_series;

alter table public.books drop column if exists series_position;
alter table public.books drop column if exists series_id;

drop table if exists public.book_series;

-- ============================================================== 4. adopt_library
-- As in `20260916000000_standalone_collections.sql`, carrying the reader's
-- own series along with shelves and tags.
create or replace function public.adopt_library(p_from uuid, p_to uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_from is null or p_to is null or p_from = p_to then
    raise exception 'two different accounts are required';
  end if;

  delete from public.reading_events where user_id = p_to;
  delete from public.memories where user_id = p_to;
  delete from public.user_books where user_id = p_to;  -- cascades tags/comments
  delete from public.tags where user_id = p_to;
  delete from public.shelves where user_id = p_to;
  delete from public.series where user_id = p_to;

  update public.shelves        set user_id = p_to where user_id = p_from;
  update public.tags           set user_id = p_to where user_id = p_from;
  update public.series         set user_id = p_to where user_id = p_from;
  update public.user_books     set user_id = p_to where user_id = p_from;
  update public.book_tags      set user_id = p_to where user_id = p_from;
  update public.book_comments  set user_id = p_to where user_id = p_from;
  update public.reading_events set user_id = p_to where user_id = p_from;
  update public.memories       set user_id = p_to where user_id = p_from;

  update public.profiles to_profile
     set reading_goal = coalesce(from_profile.reading_goal, to_profile.reading_goal)
    from public.profiles from_profile
   where to_profile.id = p_to and from_profile.id = p_from;
end;
$$;

revoke execute on function public.adopt_library(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.adopt_library(uuid, uuid) to service_role;
