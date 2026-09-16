-- popular_books: the search tab's "our readers read" row.
--
-- user_books is private per reader (RLS), so no client can count across
-- readers itself. This security-definer function returns only the shared
-- `books` catalogue rows, ordered by how many distinct readers have each on
-- their shelf — never who, and never a count for a book fewer than two
-- readers have, so one reader's shelf can't be read back through it.

create or replace function public.popular_books(p_limit integer default 20)
returns setof public.books
language sql
stable
security definer
set search_path = ''
as $$
  select b.*
  from public.books b
  join (
    select ub.book_id, count(distinct ub.user_id) as readers, max(ub.updated_at) as latest
    from public.user_books ub
    group by ub.book_id
    having count(distinct ub.user_id) >= 2
  ) p on p.book_id = b.id
  order by p.readers desc, p.latest desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke execute on function public.popular_books(integer) from public, anon;
grant execute on function public.popular_books(integer) to authenticated;
