-- Security and performance hardening of the baseline schema.
--
-- Four things change here:
--
-- 1. Every policy calls `(select auth.uid())` rather than `auth.uid()`.
--    Postgres treats the bare call as volatile-per-row and re-evaluates
--    it for every candidate row; wrapping it in a scalar sub-select lets
--    the planner hoist it into an InitPlan and evaluate it once. This is
--    the `auth_rls_initplan` finding from Supabase's database linter.
--
-- 2. `books` stops being client-writable. It was `for all ... using
--    (true) with check (true)`, which let any signed-in reader UPDATE or
--    DELETE any row in the shared cache — blanking a title for every
--    other reader, or deleting a row and cascading away the `user_books`
--    rows pointing at it. Readers now only SELECT it; the one legitimate
--    write (the cache write-back after a Google Books lookup) goes
--    through `cache_book()` below, which upserts a validated row and
--    nothing else.
--
-- 3. `user_books.updated_at` is maintained by a trigger instead of being
--    supplied by the client. The shelf is ordered by that column, so a
--    device with a skewed clock could previously pin its own rows to the
--    top (or bottom) of every reader-visible ordering permanently.
--
-- 4. `handle_new_user()` is no longer executable over the REST API. It
--    is a trigger function; it was never meant to be callable as
--    `/rest/v1/rpc/handle_new_user`, and PostgREST exposed it only
--    because `execute` defaults to PUBLIC. This is the
--    `*_security_definer_function_executable` linter finding.

-- ------------------------------------------------------ 1. policy rewrite
drop policy if exists "user_books: select own" on public.user_books;
drop policy if exists "user_books: insert own" on public.user_books;
drop policy if exists "user_books: update own" on public.user_books;
drop policy if exists "user_books: delete own" on public.user_books;

create policy "user_books: select own"
  on public.user_books for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "user_books: insert own"
  on public.user_books for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "user_books: update own"
  on public.user_books for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "user_books: delete own"
  on public.user_books for delete
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "reading_events: select own" on public.reading_events;
drop policy if exists "reading_events: insert own" on public.reading_events;

create policy "reading_events: select own"
  on public.reading_events for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "reading_events: insert own"
  on public.reading_events for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "profiles: select own" on public.profiles;
drop policy if exists "profiles: update own" on public.profiles;
drop policy if exists "profiles: insert own" on public.profiles;

create policy "profiles: select own"
  on public.profiles for select
  to authenticated
  using ((select auth.uid()) = id);

create policy "profiles: update own"
  on public.profiles for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- The `on_auth_user_created` trigger creates this row and runs as the
-- definer, so it does not need a policy. This exists only so a reader
-- whose row somehow went missing can re-create their own — and only
-- their own — rather than being stuck with no profile at all.
create policy "profiles: insert own"
  on public.profiles for insert
  to authenticated
  with check ((select auth.uid()) = id);

-- --------------------------------------------- 2. books becomes read-only
drop policy if exists "books: anon full access" on public.books;
drop policy if exists "books: authenticated full access" on public.books;
drop policy if exists "books: authenticated read" on public.books;

create policy "books: authenticated read"
  on public.books for select
  to authenticated
  using (true);

-- The only write path into the shared cache. `security definer` so it
-- runs past the read-only policy above, but it can do exactly one thing:
-- upsert a single validated volume keyed on `google_books_id`. It cannot
-- delete, cannot touch another table, and cannot be steered into one by
-- its arguments (`search_path` is pinned, everything is a bound
-- parameter). Returns the stored row because the caller needs the
-- generated `id` to hang progress off.
create or replace function public.cache_book(
  p_google_books_id text,
  p_title           text,
  p_author          text default 'Unknown author',
  p_cover_url       text default null,
  p_page_count      integer default null,
  p_description     text default null
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
  if coalesce(btrim(p_title), '') = '' then
    raise exception 'title is required';
  end if;

  insert into public.books
    (google_books_id, title, author, cover_url, page_count, description)
  values (
    btrim(p_google_books_id),
    p_title,
    coalesce(nullif(btrim(p_author), ''), 'Unknown author'),
    p_cover_url,
    -- The column's own check rejects zero and negatives; normalise
    -- rather than fail, since a bad page count is not worth losing the
    -- whole cache write over.
    case when p_page_count is not null and p_page_count > 0
         then p_page_count end,
    p_description
  )
  on conflict (google_books_id) do update set
    title       = excluded.title,
    author      = excluded.author,
    cover_url   = coalesce(excluded.cover_url, public.books.cover_url),
    page_count  = coalesce(excluded.page_count, public.books.page_count),
    description = coalesce(excluded.description, public.books.description)
  returning * into stored;

  return stored;
end;
$$;

revoke execute on function public.cache_book(
  text, text, text, text, integer, text) from public, anon;
grant execute on function public.cache_book(
  text, text, text, text, integer, text) to authenticated;

-- ------------------------------------------- 3. server-owned updated_at
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists user_books_touch_updated_at on public.user_books;
create trigger user_books_touch_updated_at
  before update on public.user_books
  for each row execute function public.touch_updated_at();

-- ------------------------------------------------ 4. RPC surface cleanup
-- Trigger function; never meant to be reachable over PostgREST.
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- Onboarding calls this before the reader has an account, so `anon`
-- keeps its grant — but PUBLIC does not, so the grant is explicit rather
-- than inherited.
revoke execute on function public.onboarding_averages() from public;
grant execute on function public.onboarding_averages() to anon, authenticated;

-- ------------------------------------------------------- 5. missing index
-- `user_books.book_id` is a foreign key with no covering index, so
-- deleting a cached book had to sequentially scan every shelf row to
-- check the cascade.
create index if not exists user_books_book_id_idx
  on public.user_books (book_id);
