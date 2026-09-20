-- Makes the import baseline part of the import itself.
--
-- `mark_library_imported()` used to run as a second RPC after
-- `replace_library` had already committed. If it failed, the imported rows
-- stayed `imported = false` and counted in the monthly charts and pace; if
-- the reader added a book between the two calls, it marked that book as
-- imported too, because it flagged every row the reader owned.
--
-- Now `replace_library` inserts the imported rows with `imported = true`
-- and stamps `profiles.library_imported_at` in the same transaction: either
-- the whole import (library, flags, baseline) lands or none of it does, and
-- only the rows this call inserted are ever flagged. The separate function
-- is dropped so nothing can call the racy version again.

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
  -- Tag links and comments go with their shelf rows (on delete cascade).
  delete from public.user_books where user_id = caller;

  -- Every row inserted here is imported history — flagged as it's written,
  -- never afterwards by a sweep over the reader's whole shelf.
  insert into public.user_books
    (book_id, status, current_page, rating, started_at, finished_at, imported)
  select distinct on (book_id)
    book_id, status, current_page, rating, started_at, finished_at, true
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

  -- The pace chart's baseline, from the server clock, in the same
  -- transaction as the rows it describes.
  update public.profiles set library_imported_at = now() where id = caller;

  return inserted;
end;
$$;

revoke execute on function public.replace_library(jsonb) from public, anon;
grant execute on function public.replace_library(jsonb) to authenticated;

drop function if exists public.mark_library_imported();
