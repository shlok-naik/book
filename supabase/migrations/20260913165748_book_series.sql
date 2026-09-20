-- Series: "Dune" is book 1 of the Dune series, "Dune Messiah" book 2.
--
-- A series is a property of the *book*, shared by every reader the same
-- way the `books` cache is — "Dune #2" means the same thing to everyone —
-- rather than a private per-reader grouping like tags. So it follows the
-- cache's rules: readable by any signed-in reader, writable only through a
-- security-definer function that does one validated thing.
--
-- Readers are the ones who fill it in (`series <series> [#n] <book>`), which
-- means one reader's write changes what every other reader sees. Two rules
-- keep that from being a vandalism vector:
--
--   * you can only file a book you have on your own shelf;
--   * first writer wins — once a book is in a series, changing its series
--     or its number is refused, *unless* nobody else has that book on their
--     shelf (so a reader can still fix their own typo on an obscure book,
--     but can't rename "Dune" for everyone who has it).
--
-- Series names are matched case- and space-insensitively, so "the expanse",
-- "The  Expanse" and "The Expanse" are one series; the first spelling
-- stored is the one shown.

create table if not exists public.book_series (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(btrim(name)) between 1 and 80),
  created_at timestamptz not null default now()
);

create unique index if not exists book_series_name_key
  on public.book_series (lower(regexp_replace(btrim(name), '\s+', ' ', 'g')));

alter table public.book_series enable row level security;

drop policy if exists "book_series: authenticated read" on public.book_series;
create policy "book_series: authenticated read"
  on public.book_series for select
  to authenticated
  using (true);

alter table public.books
  add column if not exists series_id uuid
    references public.book_series (id) on delete set null,
  -- numeric, not integer: novellas are numbered 1.5, 2.5 and so on.
  add column if not exists series_position numeric(5, 1)
    check (series_position is null or series_position > 0);

create index if not exists books_series_id_idx
  on public.books (series_id, series_position)
  where series_id is not null;

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
    raise exception 'book is not on your shelf' using errcode = 'P0002';
  end if;

  select * into existing from public.books where id = p_book_id for update;

  select * into series from public.book_series
  where lower(name) = lower(clean_name);
  if series.id is null then
    insert into public.book_series (name) values (clean_name)
    on conflict do nothing
    returning * into series;
    if series.id is null then
      select * into series from public.book_series
      where lower(name) = lower(clean_name);
    end if;
  end if;

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
