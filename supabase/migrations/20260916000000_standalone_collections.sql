-- Standalone collections: shelves, tags and series become things a reader
-- *makes first* and *applies afterwards*.
--
--   make shelf <name>    → a row in `shelves`            → move <book> <shelf>
--   make tag <tag>       → a row in `tags`               → add tag <tag> <book>
--   make series <name>   → `book_series` + `reader_series` → add series <series> [#n] <book>
--
-- The library page's "+" panel runs exactly the same creation paths. Nothing
-- that adds or changes a *book* creates a collection as a side effect any
-- more: before this migration `book_tags.tag` was free text (so tagging a
-- book invented the tag) and `set_book_series` inserted any series name it
-- was handed. Both now require the collection to exist.
--
-- Sections:
--   1. shelves (+ user_books.shelf_id, touch_updated_at)
--   2. tags (+ book_tags.tag_id, backfill)
--   3. series (reader_series, make_book_series, set_book_series)
--   4. replace_library — the Goodreads import only links tags that exist
--   5. adopt_library   — account linking carries the new tables along

-- =================================================================== 1. shelves
-- A custom shelf is private to its reader, like tags. The four built-in
-- shelves (to read, reading, finished, did not finish) are *not* rows: they
-- are `user_books.status`, and stay that way — status is what stats, the
-- journal and "currently reading" all key off.
--
-- A book on a custom shelf keeps its status. `shelf_id` only says where the
-- book is *shown*: null → in its status section, set → in that shelf's
-- section. So `finish Dune` on a book shelved under "summer" still counts
-- as a finished book, without pulling it off "summer"; only `move` (or a
-- drag on the library page) changes `shelf_id`.
create table if not exists public.shelves (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 40),
  created_at timestamptz not null default now(),
  -- Target of user_books' composite foreign key below.
  unique (user_id, id),
  -- A custom shelf named like a built-in one would make `move Dune reading`
  -- ambiguous. Mirrors `CollectionNames.reservedShelfNames` in the app.
  constraint shelves_name_not_reserved check (
    lower(regexp_replace(btrim(name), '\s+', ' ', 'g')) not in (
      'tbr', 'to read', 'to be read', 'reading', 'finished', 'dnf',
      'did not finish'
    )
  )
);

-- One "Summer Reads" per reader however it was capitalised or spaced.
create unique index if not exists shelves_name_per_reader
  on public.shelves (user_id, lower(regexp_replace(btrim(name), '\s+', ' ', 'g')));

alter table public.shelves enable row level security;

drop policy if exists "shelves: select own" on public.shelves;
create policy "shelves: select own"
  on public.shelves for select to authenticated
  using ((select auth.uid()) = user_id);
drop policy if exists "shelves: insert own" on public.shelves;
create policy "shelves: insert own"
  on public.shelves for insert to authenticated
  with check ((select auth.uid()) = user_id);

alter table public.user_books
  add column if not exists shelf_id uuid;

-- Composite, so a shelf row can only ever point at a shelf its own reader
-- made — RLS on `user_books` checks the row's owner, not the shelf's.
-- `on update cascade` lets `adopt_library` move shelves between accounts
-- without tripping the key; `set null (shelf_id)` (not the whole key) keeps
-- `user_id` intact if a shelf is ever removed, dropping its books back into
-- their status sections.
alter table public.user_books
  drop constraint if exists user_books_shelf_fkey;
alter table public.user_books
  add constraint user_books_shelf_fkey
    foreign key (user_id, shelf_id) references public.shelves (user_id, id)
    on update cascade
    on delete set null (shelf_id);

create index if not exists user_books_shelf_id_idx
  on public.user_books (user_id, shelf_id)
  where shelf_id is not null;

-- Same function as `20260915030000_account_linking`, plus: moving a book to
-- another *custom* shelf resets its manual position exactly as a status
-- change does — an index from the old section means nothing in the new one.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name = 'user_books' then
    if (new.status is distinct from old.status
        or new.shelf_id is distinct from old.shelf_id)
       and new.shelf_position is not distinct from old.shelf_position then
      new.shelf_position = null;
    end if;
    if (to_jsonb(new) - 'shelf_position' - 'updated_at' - 'user_id')
       = (to_jsonb(old) - 'shelf_position' - 'updated_at' - 'user_id') then
      new.updated_at = old.updated_at;
      return new;
    end if;
  end if;
  -- Nested rather than `and`-ed: plpgsql doesn't guarantee short-circuit
  -- evaluation, and `new.body` doesn't exist on any other table.
  if tg_table_name = 'book_comments' then
    if new.body is not distinct from old.body then
      new.updated_at = old.updated_at;
      return new;
    end if;
  end if;
  new.updated_at = now();
  return new;
end;
$$;

-- ====================================================================== 2. tags
create table if not exists public.tags (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 40),
  created_at timestamptz not null default now(),
  unique (user_id, id)
);

-- Same identity rule `book_tags_unique_per_book` already used.
create unique index if not exists tags_name_per_reader
  on public.tags (user_id, lower(btrim(name)));

alter table public.tags enable row level security;

drop policy if exists "tags: select own" on public.tags;
create policy "tags: select own"
  on public.tags for select to authenticated
  using ((select auth.uid()) = user_id);
drop policy if exists "tags: insert own" on public.tags;
create policy "tags: insert own"
  on public.tags for insert to authenticated
  with check ((select auth.uid()) = user_id);

-- Every tag a reader has already used becomes a standalone tag of theirs,
-- spelled the way they first typed it.
insert into public.tags (user_id, name, created_at)
select distinct on (user_id, lower(btrim(tag)))
  user_id, btrim(tag), created_at
from public.book_tags
order by user_id, lower(btrim(tag)), created_at
on conflict do nothing;

alter table public.book_tags
  add column if not exists tag_id uuid;

update public.book_tags bt
   set tag_id = t.id
  from public.tags t
 where bt.tag_id is null
   and t.user_id = bt.user_id
   and lower(btrim(t.name)) = lower(btrim(bt.tag));

alter table public.book_tags
  alter column tag_id set not null;

alter table public.book_tags
  drop constraint if exists book_tags_tag_fkey;
alter table public.book_tags
  add constraint book_tags_tag_fkey
    foreign key (user_id, tag_id) references public.tags (user_id, id)
    on update cascade
    on delete cascade;

create unique index if not exists book_tags_tag_once_per_book
  on public.book_tags (user_book_id, tag_id);
create index if not exists book_tags_tag_id_idx
  on public.book_tags (tag_id);

-- `book_tags.tag` stays, as the tag's name copied onto the link: library
-- search, the book page and the CSV export all read it without a join. It
-- is never trusted from the client — this trigger fills it from `tags`, and
-- refuses a `tag_id` that isn't one of the caller's own tags (the foreign
-- key would too, but with a message nobody can act on).
create or replace function public.book_tags_fill_name()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  select t.name into new.tag
  from public.tags t
  where t.id = new.tag_id and t.user_id = new.user_id;
  if new.tag is null then
    raise exception 'tag does not exist'
      using errcode = 'P0002', hint = 'tag_missing';
  end if;
  return new;
end;
$$;

revoke execute on function public.book_tags_fill_name() from public, anon, authenticated;

drop trigger if exists book_tags_fill_name on public.book_tags;
create trigger book_tags_fill_name
  before insert or update of tag_id on public.book_tags
  for each row execute function public.book_tags_fill_name();

-- ==================================================================== 3. series
-- `book_series` stays shared (see `20260915010000_book_series`): "Dune #2"
-- means the same thing to everyone. What's new is the reader's own list of
-- series they have made — `reader_series` — which is what `add series`
-- requires membership of, and what the "+" panel's series tab lists.
--
-- `make series dune` when another reader already made "Dune" is therefore
-- not an error: it joins the shared series to *your* list. Only making a
-- series already on your own list is refused.
create table if not exists public.reader_series (
  user_id    uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  series_id  uuid not null references public.book_series (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, series_id)
);

create index if not exists reader_series_series_id_idx
  on public.reader_series (series_id);

alter table public.reader_series enable row level security;

-- Read-only to readers: the one write path is `make_book_series`.
drop policy if exists "reader_series: select own" on public.reader_series;
create policy "reader_series: select own"
  on public.reader_series for select to authenticated
  using ((select auth.uid()) = user_id);

-- Every series a reader already has a book filed in is one they made.
insert into public.reader_series (user_id, series_id)
select distinct ub.user_id, b.series_id
from public.user_books ub
join public.books b on b.id = ub.book_id
where b.series_id is not null
on conflict do nothing;

-- `make series <name>`. Returns
--   { id, name, created: bool, already_yours: bool }
-- `created` — nobody had this series before; `already_yours` — nothing
-- changed, the caller had already made it.
create or replace function public.make_book_series(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller     uuid := auth.uid();
  clean_name text := regexp_replace(btrim(coalesce(p_name, '')), '\s+', ' ', 'g');
  series     public.book_series;
  created    boolean := false;
  linked     integer;
begin
  if caller is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  if char_length(clean_name) not between 1 and 80 then
    raise exception 'series name must be 1-80 characters' using errcode = '22023';
  end if;

  select * into series from public.book_series
  where lower(regexp_replace(btrim(name), '\s+', ' ', 'g')) = lower(clean_name);

  if series.id is null then
    insert into public.book_series (name) values (clean_name)
    on conflict do nothing
    returning * into series;
    if series.id is null then
      -- Lost a race with another reader making the same name.
      select * into series from public.book_series
      where lower(regexp_replace(btrim(name), '\s+', ' ', 'g')) = lower(clean_name);
    else
      created := true;
    end if;
  end if;

  insert into public.reader_series (user_id, series_id)
  values (caller, series.id)
  on conflict do nothing;
  get diagnostics linked = row_count;

  return jsonb_build_object(
    'id', series.id,
    'name', series.name,
    'created', created,
    'already_yours', linked = 0
  );
end;
$$;

revoke execute on function public.make_book_series(text) from public, anon;
grant execute on function public.make_book_series(text) to authenticated;

-- `add series <series> [#n] <book>`. Same rules as before (the book must be
-- on your shelf; first writer wins for shared books), except the series is
-- no longer created here: it must already be on the caller's own list.
create or replace function public.set_book_series(
  p_book_id     uuid,
  p_series_name text,
  p_position    numeric default null
)
returns public.books
language plpgsql
security definer
set search_path = public
as $$
declare
  caller      uuid := auth.uid();
  clean_name  text := regexp_replace(btrim(coalesce(p_series_name, '')), '\s+', ' ', 'g');
  series      public.book_series;
  existing    public.books;
  shared      boolean;
  stored      public.books;
begin
  if caller is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  if char_length(clean_name) not between 1 and 80 then
    raise exception 'series name must be 1-80 characters' using errcode = '22023';
  end if;
  if p_position is not null and (p_position <= 0 or p_position >= 10000) then
    raise exception 'series number out of range' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.user_books
    where book_id = p_book_id and user_id = caller
  ) then
    raise exception 'book is not on your shelf'
      using errcode = 'P0002', hint = 'book_not_on_shelf';
  end if;

  select s.* into series
  from public.book_series s
  join public.reader_series rs
    on rs.series_id = s.id and rs.user_id = caller
  where lower(regexp_replace(btrim(s.name), '\s+', ' ', 'g')) = lower(clean_name);
  if series.id is null then
    raise exception 'series does not exist'
      using errcode = 'P0002', hint = 'series_missing';
  end if;

  select * into existing from public.books where id = p_book_id for update;

  shared := exists (
    select 1 from public.user_books
    where book_id = p_book_id and user_id <> caller
  );

  -- First writer wins, for books other readers have too.
  if shared and existing.series_id is not null and (
       existing.series_id <> series.id
       or (p_position is not null
           and existing.series_position is not null
           and existing.series_position <> round(p_position, 1))
     ) then
    raise exception 'book is already filed in a series'
      using errcode = 'P0001', hint = 'series_locked';
  end if;

  update public.books set
    series_id       = series.id,
    series_position = case
                        when p_position is null then
                          case when existing.series_id = series.id
                               then existing.series_position end
                        else round(p_position, 1)
                      end
  where id = p_book_id
  returning * into stored;

  return stored;
end;
$$;

revoke execute on function public.set_book_series(uuid, text, numeric)
  from public, anon;
grant execute on function public.set_book_series(uuid, text, numeric)
  to authenticated;

-- ============================================================ 4. replace_library
-- As in `20260915020000_replace_library`, except tags: each name in an
-- element's `tags` is linked only if the caller already has a tag of that
-- name. The import makes the file's tags first, through the same creation
-- path as `make tag` (see `ImportController.confirm`), so this function
-- never invents one. Standalone tags, shelves and series are kept, like
-- memories and the goal: they aren't books.
create or replace function public.replace_library(p_books jsonb)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  caller   uuid := auth.uid();
  inserted integer;
begin
  if caller is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  if jsonb_typeof(p_books) <> 'array' then
    raise exception 'books must be a JSON array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_books) > 5000 then
    raise exception 'too many books' using errcode = '22023';
  end if;

  delete from public.reading_events where user_id = caller;
  -- Tags links and comments go with their shelf rows (on delete cascade).
  delete from public.user_books where user_id = caller;

  insert into public.user_books
    (book_id, status, current_page, rating, started_at, finished_at)
  select distinct on (book_id)
    book_id, status, current_page, rating, started_at, finished_at
  from (
    select
      (b ->> 'book_id')::uuid as book_id,
      b ->> 'status' as status,
      greatest(coalesce((b ->> 'current_page')::integer, 0), 0) as current_page,
      case when (b ->> 'rating')::numeric > 0 and (b ->> 'rating')::numeric <= 5
           then round((b ->> 'rating')::numeric * 2) / 2 end as rating,
      coalesce((b ->> 'started_at')::timestamptz, now()) as started_at,
      case when b ->> 'status' = 'finished'
           then (b ->> 'finished_at')::timestamptz end as finished_at
    from jsonb_array_elements(p_books) as b
  ) as incoming
  where exists (select 1 from public.books where id = incoming.book_id);
  get diagnostics inserted = row_count;

  -- `tag` is filled by the `book_tags_fill_name` trigger.
  insert into public.book_tags (user_book_id, tag_id)
  select distinct ub.id, t.id
  from jsonb_array_elements(p_books) as b
  join public.user_books ub
    on ub.book_id = (b ->> 'book_id')::uuid and ub.user_id = caller
  cross join lateral jsonb_array_elements_text(
    case when jsonb_typeof(b -> 'tags') = 'array' then b -> 'tags' else '[]' end
  ) as tag(value)
  join public.tags t
    on t.user_id = caller and lower(btrim(t.name)) = lower(btrim(tag.value))
  on conflict do nothing;

  insert into public.book_comments (user_book_id, body)
  select ub.id, left(btrim(note.value), 1000)
  from jsonb_array_elements(p_books) as b
  join public.user_books ub
    on ub.book_id = (b ->> 'book_id')::uuid and ub.user_id = caller
  cross join lateral jsonb_array_elements_text(
    case when jsonb_typeof(b -> 'comments') = 'array' then b -> 'comments' else '[]' end
  ) as note(value)
  where char_length(btrim(note.value)) > 0;

  insert into public.reading_events (action, title, occurred_at)
  select 'finish', bk.title, ub.finished_at
  from public.user_books ub
  join public.books bk on bk.id = ub.book_id
  where ub.user_id = caller
    and ub.status = 'finished'
    and ub.finished_at is not null;

  return inserted;
end;
$$;

revoke execute on function public.replace_library(jsonb) from public, anon;
grant execute on function public.replace_library(jsonb) to authenticated;

-- ============================================================== 5. adopt_library
-- As in `20260915030000_account_linking`, carrying shelves, tags and the
-- reader's series list with the kept library. Shelves and tags move first:
-- their composite keys cascade the new owner onto the `user_books` and
-- `book_tags` rows that point at them, and the plain updates after that
-- catch every row that doesn't.
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

  -- The kept library replaces whatever the email account had.
  delete from public.reading_events where user_id = p_to;
  delete from public.memories where user_id = p_to;
  delete from public.user_books where user_id = p_to;  -- cascades tags/comments
  delete from public.tags where user_id = p_to;
  delete from public.shelves where user_id = p_to;
  delete from public.reader_series where user_id = p_to;

  update public.shelves        set user_id = p_to where user_id = p_from;
  update public.tags           set user_id = p_to where user_id = p_from;
  update public.user_books     set user_id = p_to where user_id = p_from;
  update public.book_tags      set user_id = p_to where user_id = p_from;
  update public.book_comments  set user_id = p_to where user_id = p_from;
  update public.reading_events set user_id = p_to where user_id = p_from;
  update public.memories       set user_id = p_to where user_id = p_from;
  update public.reader_series  set user_id = p_to where user_id = p_from;

  -- The goal travels with the library it was set against.
  update public.profiles to_profile
     set reading_goal = coalesce(from_profile.reading_goal, to_profile.reading_goal)
    from public.profiles from_profile
   where to_profile.id = p_to and from_profile.id = p_from;
end;
$$;

revoke execute on function public.adopt_library(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.adopt_library(uuid, uuid) to service_role;
