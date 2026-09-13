-- Goodreads import: replace the caller's whole library in one transaction.
--
-- The import is a full wipe by design — the reader confirms that their
-- current books, tags, comments and reading history are replaced by the
-- file's. Doing it in one function call is what makes that safe: either
-- the old library is gone *and* the new one is in, or (on any error — a bad
-- status, a cast that fails, a constraint) nothing changed at all. A
-- client-side delete followed by N inserts could die halfway and leave an
-- empty shelf.
--
-- Matching titles to catalogue books happens in the app before this is
-- called (`cache_book` has already created every `books` row), so each
-- element only references a `books.id`.
--
-- `security invoker`: RLS on every table below is what keeps it to the
-- caller's own rows, exactly as if the app had issued each statement. Kept
-- deliberately: memories (not part of the library) and the reading goal.
--
-- Each element of p_books:
--   { book_id uuid, status text, current_page int, rating numeric,
--     started_at timestamptz, finished_at timestamptz,
--     tags text[], comments text[] }

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
  -- Tags and comments go with their shelf rows (on delete cascade).
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

  insert into public.book_tags (user_book_id, tag)
  select ub.id, btrim(tag.value)
  from jsonb_array_elements(p_books) as b
  join public.user_books ub
    on ub.book_id = (b ->> 'book_id')::uuid and ub.user_id = caller
  cross join lateral jsonb_array_elements_text(
    case when jsonb_typeof(b -> 'tags') = 'array' then b -> 'tags' else '[]' end
  ) as tag(value)
  where char_length(btrim(tag.value)) between 1 and 40
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

  -- A dated finish is a real moment in the reader's history: journal it,
  -- so the stats page's journal and streaks reflect the imported library.
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
