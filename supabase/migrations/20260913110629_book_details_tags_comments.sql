-- The book detail page: richer catalogue info and editions (shared caches,
-- written only through security-definer functions like `cache_book`),
-- per-reader tags and comments, the edition a reader owns, and a manual
-- order for drag-to-reorder on the library page.
--
-- Caching follows exactly the convention `books` already set:
--   * the shared tables are readable by any signed-in reader and
--     writable by none — the only write path is a `security definer`
--     function that can do one validated thing;
--   * a `*_fetched_at` timestamp on `books` records that Google Books has
--     already been asked, so "fetched, and there was nothing" (zero
--     editions, a volume with no publisher) is a cache *hit*, not a miss
--     that re-queries Google Books on every visit.

-- ------------------------------------------------ 1. extended book info
alter table public.books
  add column if not exists subtitle           text,
  add column if not exists publisher          text,
  add column if not exists published_date     text,  -- Google's own "2005", "2005-08", or "2005-08-02"
  add column if not exists categories         text[] not null default '{}',
  add column if not exists language           text,
  add column if not exists isbn_10            text,
  add column if not exists isbn_13            text,
  add column if not exists average_rating     numeric(2, 1),
  add column if not exists ratings_count      integer,
  add column if not exists maturity_rating    text,
  add column if not exists preview_link       text,
  -- Null until `cache_book_details` has run once for this volume.
  add column if not exists details_fetched_at  timestamptz,
  -- Null until `cache_book_editions` has run once for this book.
  add column if not exists editions_fetched_at timestamptz;

-- The one write path for the columns above. Updates an *existing* cache
-- row only — the book was already cached by `cache_book` when it reached a
-- shelf, and this function must not be a second way to insert catalogue
-- rows. Every text argument is optional: Google omits fields freely, and
-- a missing publisher is not worth failing the write over.
create or replace function public.cache_book_details(
  p_google_books_id text,
  p_description     text    default null,
  p_subtitle        text    default null,
  p_publisher       text    default null,
  p_published_date  text    default null,
  p_categories      text[]  default '{}',
  p_language        text    default null,
  p_isbn_10         text    default null,
  p_isbn_13         text    default null,
  p_average_rating  numeric default null,
  p_ratings_count   integer default null,
  p_maturity_rating text    default null,
  p_preview_link    text    default null,
  p_page_count      integer default null
)
returns public.books
language plpgsql
security definer
set search_path = public
as $$
declare
  stored public.books;
begin
  if coalesce(btrim(p_google_books_id), '') = '' then
    raise exception 'google_books_id is required';
  end if;

  update public.books set
    -- The volume endpoint's description is the full blurb; the search
    -- endpoint's (what `cache_book` stored) can be truncated. Prefer the
    -- new one, but never replace something with nothing.
    description        = coalesce(nullif(btrim(p_description), ''), description),
    subtitle           = nullif(btrim(p_subtitle), ''),
    publisher          = nullif(btrim(p_publisher), ''),
    published_date     = nullif(btrim(p_published_date), ''),
    categories         = coalesce(p_categories[1:20], '{}'),
    language           = nullif(btrim(p_language), ''),
    isbn_10            = nullif(btrim(p_isbn_10), ''),
    isbn_13            = nullif(btrim(p_isbn_13), ''),
    average_rating     = case when p_average_rating between 0 and 5
                              then round(p_average_rating, 1) end,
    ratings_count      = case when p_ratings_count >= 0 then p_ratings_count end,
    maturity_rating    = nullif(btrim(p_maturity_rating), ''),
    preview_link       = nullif(btrim(p_preview_link), ''),
    page_count         = coalesce(
                           case when p_page_count > 0 then p_page_count end,
                           page_count),
    details_fetched_at = now()
  where google_books_id = btrim(p_google_books_id)
  returning * into stored;

  if stored.id is null then
    raise exception 'book % is not cached', p_google_books_id;
  end if;
  return stored;
end;
$$;

revoke execute on function public.cache_book_details(
  text, text, text, text, text, text[], text, text, text, numeric, integer,
  text, text, integer) from public, anon;
grant execute on function public.cache_book_details(
  text, text, text, text, text, text[], text, text, text, numeric, integer,
  text, text, integer) to authenticated;

-- ---------------------------------------------------------- 2. editions
-- The ebook and physical editions of a cached book, as found on Google
-- Books. Shared across readers the same way `books` is: every reader
-- asking about Dune should hit one cache, not a per-reader copy.
create table if not exists public.book_editions (
  id              uuid primary key default gen_random_uuid(),
  book_id         uuid not null references public.books (id) on delete cascade,
  google_books_id text not null,
  title           text not null,
  subtitle        text,
  author          text not null default 'Unknown author',
  -- Only these two formats are ever stored: the filtering happens in the
  -- client before the write, and this check makes it impossible to store
  -- anything else even if a future client forgets to.
  format          text not null check (format in ('ebook', 'physical')),
  publisher       text,
  published_date  text,
  page_count      integer check (page_count is null or page_count > 0),
  language        text,
  isbn_13         text,
  isbn_10         text,
  cover_url       text,
  created_at      timestamptz not null default now(),
  unique (book_id, google_books_id),
  -- The target of `user_books`' composite foreign key below, which is
  -- what guarantees an owned edition belongs to the same book.
  unique (book_id, id)
);

alter table public.book_editions enable row level security;

create policy "book_editions: authenticated read"
  on public.book_editions for select
  to authenticated
  using (true);

-- Replaces a book's cached edition list in one call and stamps
-- `books.editions_fetched_at`, so an empty list is remembered as empty.
-- Upserts on (book_id, google_books_id) rather than delete-then-insert:
-- an edition's `id` is what a reader's "I own this one" points at, and it
-- must survive a re-fetch. Editions that dropped out of Google's results
-- are deliberately kept — a reader may already own one.
create or replace function public.cache_book_editions(
  p_book_id  uuid,
  p_editions jsonb
)
returns setof public.book_editions
language plpgsql
security definer
set search_path = public
as $$
declare
  edition jsonb;
begin
  if not exists (select 1 from public.books where id = p_book_id) then
    raise exception 'book % is not cached', p_book_id;
  end if;
  if jsonb_typeof(p_editions) <> 'array' then
    raise exception 'editions must be a JSON array';
  end if;
  if jsonb_array_length(p_editions) > 40 then
    raise exception 'too many editions';
  end if;

  for edition in select * from jsonb_array_elements(p_editions) loop
    if coalesce(btrim(edition ->> 'google_books_id'), '') = ''
       or coalesce(btrim(edition ->> 'title'), '') = '' then
      continue;  -- unusable row; skip rather than fail the whole list
    end if;

    insert into public.book_editions (
      book_id, google_books_id, title, subtitle, author, format, publisher,
      published_date, page_count, language, isbn_13, isbn_10, cover_url
    ) values (
      p_book_id,
      btrim(edition ->> 'google_books_id'),
      edition ->> 'title',
      nullif(btrim(edition ->> 'subtitle'), ''),
      coalesce(nullif(btrim(edition ->> 'author'), ''), 'Unknown author'),
      edition ->> 'format',
      nullif(btrim(edition ->> 'publisher'), ''),
      nullif(btrim(edition ->> 'published_date'), ''),
      case when (edition ->> 'page_count') ~ '^[0-9]+$'
                and (edition ->> 'page_count')::integer > 0
           then (edition ->> 'page_count')::integer end,
      nullif(btrim(edition ->> 'language'), ''),
      nullif(btrim(edition ->> 'isbn_13'), ''),
      nullif(btrim(edition ->> 'isbn_10'), ''),
      nullif(btrim(edition ->> 'cover_url'), '')
    )
    on conflict (book_id, google_books_id) do update set
      title          = excluded.title,
      subtitle       = excluded.subtitle,
      author         = excluded.author,
      format         = excluded.format,
      publisher      = excluded.publisher,
      published_date = excluded.published_date,
      page_count     = excluded.page_count,
      language       = excluded.language,
      isbn_13        = excluded.isbn_13,
      isbn_10        = excluded.isbn_10,
      cover_url      = coalesce(excluded.cover_url, public.book_editions.cover_url);
  end loop;

  update public.books set editions_fetched_at = now() where id = p_book_id;

  return query
    select * from public.book_editions
    where book_id = p_book_id
    order by format, published_date desc nulls last, title;
end;
$$;

revoke execute on function public.cache_book_editions(uuid, jsonb)
  from public, anon;
grant execute on function public.cache_book_editions(uuid, jsonb)
  to authenticated;

-- ----------------------------------------- 3. owned edition + shelf order
alter table public.user_books
  add column if not exists owned_edition_id uuid,
  -- Manual order within a shelf section, set by drag-to-reorder. Null
  -- means "never placed by hand": those rows sort ahead of placed ones,
  -- most recently updated first — exactly the order the shelf had before
  -- this column existed.
  add column if not exists shelf_position double precision;

-- Composite, so an owned edition must be an edition *of this book*; only
-- the edition column is nulled if that edition is ever removed.
alter table public.user_books
  drop constraint if exists user_books_owned_edition_fkey,
  add constraint user_books_owned_edition_fkey
    foreign key (book_id, owned_edition_id)
    references public.book_editions (book_id, id)
    on delete set null (owned_edition_id);

create index if not exists user_books_owned_edition_idx
  on public.user_books (book_id, owned_edition_id)
  where owned_edition_id is not null;

-- `updated_at` orders the shelf and decides which book is "currently
-- reading" on the add tab, so it has to mean "the reader did something
-- with this book". Dragging a book around rewrites `shelf_position` on
-- every row of the section it lands in — none of which the reader read.
-- A write that changes nothing but the position keeps its old timestamp.
--
-- And a status change that doesn't also place the row clears its
-- position: a stale index from its previous section would otherwise drop
-- a newly finished book somewhere arbitrary in "finished", instead of at
-- the top where every other just-changed book lands.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name = 'user_books' then
    if new.status is distinct from old.status
       and new.shelf_position is not distinct from old.shelf_position then
      new.shelf_position = null;
    end if;
    if (to_jsonb(new) - 'shelf_position' - 'updated_at')
       = (to_jsonb(old) - 'shelf_position' - 'updated_at') then
      new.updated_at = old.updated_at;
      return new;
    end if;
  end if;
  new.updated_at = now();
  return new;
end;
$$;

-- Writes a whole section's order in one statement. `security invoker`
-- (the default): RLS on `user_books` is what limits it to the caller's
-- own rows, so an id belonging to someone else simply updates nothing.
create or replace function public.set_shelf_order(p_ordered_ids uuid[])
returns void
language sql
set search_path = public
as $$
  update public.user_books ub
     set shelf_position = ordered.position - 1
    from unnest(p_ordered_ids) with ordinality as ordered(id, position)
   where ub.id = ordered.id;
$$;

revoke execute on function public.set_shelf_order(uuid[]) from public, anon;
grant execute on function public.set_shelf_order(uuid[]) to authenticated;

-- ------------------------------------------------------ 4. tags/comments
-- Private per reader, and attached to a shelf row rather than a catalogue
-- book: a tag is "my" label on "my" copy, and removing the book from the
-- shelf takes its tags and comments with it.
create table if not exists public.book_tags (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid()
                 references auth.users (id) on delete cascade,
  user_book_id uuid not null references public.user_books (id) on delete cascade,
  tag          text not null check (char_length(btrim(tag)) between 1 and 40),
  created_at   timestamptz not null default now()
);

-- One "sci-fi" per book regardless of how it was capitalised.
create unique index if not exists book_tags_unique_per_book
  on public.book_tags (user_book_id, lower(btrim(tag)));

create table if not exists public.book_comments (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid()
                 references auth.users (id) on delete cascade,
  user_book_id uuid not null references public.user_books (id) on delete cascade,
  body         text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists book_comments_user_book_idx
  on public.book_comments (user_book_id, created_at);
create index if not exists book_tags_user_id_idx on public.book_tags (user_id);
create index if not exists book_comments_user_id_idx on public.book_comments (user_id);

drop trigger if exists book_comments_touch_updated_at on public.book_comments;
create trigger book_comments_touch_updated_at
  before update on public.book_comments
  for each row execute function public.touch_updated_at();

alter table public.book_tags enable row level security;
alter table public.book_comments enable row level security;

-- Insert/update also check the shelf row is the caller's own: `user_id`
-- alone would let a reader attach a note to someone else's user_books id.
create policy "book_tags: select own"
  on public.book_tags for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "book_tags: insert own"
  on public.book_tags for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.user_books ub
      where ub.id = user_book_id and ub.user_id = (select auth.uid())
    )
  );
create policy "book_tags: delete own"
  on public.book_tags for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy "book_comments: select own"
  on public.book_comments for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "book_comments: insert own"
  on public.book_comments for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.user_books ub
      where ub.id = user_book_id and ub.user_id = (select auth.uid())
    )
  );
create policy "book_comments: update own"
  on public.book_comments for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "book_comments: delete own"
  on public.book_comments for delete to authenticated
  using ((select auth.uid()) = user_id);
