-- popular_books: count only *other* readers.
--
-- The first version counted the caller too, so a reader with a book on
-- their own shelf saw it in "our readers read" as soon as one other person
-- shelved it — learning that exactly one other reader has that book. Now a
-- book needs at least two readers besides the caller, and the caller's own
-- rows never move the order.

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
    where ub.user_id <> (select auth.uid())
    group by ub.book_id
    having count(distinct ub.user_id) >= 2
  ) p on p.book_id = b.id
  order by p.readers desc, p.latest desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
$$;

revoke execute on function public.popular_books(integer) from public, anon;
grant execute on function public.popular_books(integer) to authenticated;
