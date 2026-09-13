-- `cache_book_details` must never change a book's page count once it has
-- one. Every reader's progress percentage on that book is `current_page /
-- page_count`, and the volume endpoint often describes a different printing
-- than the search result `cache_book` stored — opening Doctor Sleep's detail
-- page replaced 703 with 639, silently moving a reader from 78% to 86%.
-- The count is only filled in when the cache didn't have one.
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
    -- Existing count wins; see the header comment.
    page_count         = coalesce(
                           page_count,
                           case when p_page_count > 0 then p_page_count end),
    details_fetched_at = now()
  where google_books_id = btrim(p_google_books_id)
  returning * into stored;

  if stored.id is null then
    raise exception 'book % is not cached', p_google_books_id;
  end if;
  return stored;
end;
$$;
