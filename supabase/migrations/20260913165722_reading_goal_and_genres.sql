-- Reading goals, genres for the stats page, and a missing delete policy.
--
-- 1. `profiles.reading_goal` — how many books the reader wants to finish
--    in a calendar year. One number that carries over from year to year;
--    progress against it is always "books finished this year", counted
--    from `user_books.finished_at`, so nothing here needs resetting on
--    January 1st. Stored on the profile rather than the device so it
--    follows the reader's account when an email is linked.
--
-- 2. `cache_book` also stores Google's categories. Until now they were only
--    written by `cache_book_details`, i.e. once someone opened the book's
--    detail page, so the stats page's genre breakdown would have been empty
--    for almost every shelf. A search result already carries them. Existing
--    categories are never replaced by a search result's (the volume
--    endpoint's are the more specific ones). While rewriting it, a re-cache
--    stops replacing an existing page count too — the same rule
--    `20260914010000_keep_cached_page_count` gave `cache_book_details`,
--    since every reader's percentage on the book hangs off that number.
--
-- 3. `reading_events` had select and insert policies but no delete policy,
--    so `ReadingEventRepository.deleteForTitle` — what `delete <book>` uses
--    to clear a book's journal lines — silently deleted nothing. RLS turns a
--    delete without a matching policy into a zero-row delete, not an error.

-- ----------------------------------------------------------- 1. goal
alter table public.profiles
  add column if not exists reading_goal integer
    check (reading_goal is null or reading_goal between 1 and 1000);

-- ------------------------------------------------ 2. cache_book genres
drop function if exists public.cache_book(text, text, text, text, integer, text);

create or replace function public.cache_book(
  p_google_books_id text,
  p_title           text,
  p_author          text    default 'Unknown author',
  p_cover_url       text    default null,
  p_page_count      integer default null,
  p_description     text    default null,
  p_categories      text[]  default '{}'
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
    (google_books_id, title, author, cover_url, page_count, description,
     categories)
  values (
    btrim(p_google_books_id),
    p_title,
    coalesce(nullif(btrim(p_author), ''), 'Unknown author'),
    p_cover_url,
    case when p_page_count is not null and p_page_count > 0
         then p_page_count end,
    p_description,
    coalesce(p_categories[1:20], '{}')
  )
  on conflict (google_books_id) do update set
    title       = excluded.title,
    author      = excluded.author,
    cover_url   = coalesce(excluded.cover_url, public.books.cover_url),
    page_count  = coalesce(public.books.page_count, excluded.page_count),
    description = coalesce(excluded.description, public.books.description),
    categories  = case when cardinality(public.books.categories) = 0
                       then excluded.categories
                       else public.books.categories end
  returning * into stored;

  return stored;
end;
$$;

revoke execute on function public.cache_book(
  text, text, text, text, integer, text, text[]) from public, anon;
grant execute on function public.cache_book(
  text, text, text, text, integer, text, text[]) to authenticated;

-- ------------------------------------- 3. reading_events delete policy
drop policy if exists "reading_events: delete own" on public.reading_events;
create policy "reading_events: delete own"
  on public.reading_events for delete
  to authenticated
  using ((select auth.uid()) = user_id);
