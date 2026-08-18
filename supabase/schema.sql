-- Schema for the library and onboarding features.
-- Run this once in the Supabase SQL editor (or as a migration).
--
-- Tables:
--   books      — the shared cache of Google Books volumes. One row per
--                volume; `google_books_id` is the de-duplication key the
--                cache-first lookup upserts on. Shared across every
--                reader — not owned by any one of them.
--   user_books — the reader's progress against a cached book. Owned by
--                whoever is signed in (`user_id`), including anonymous
--                Supabase Auth sessions — `user_id` is never set by the
--                app itself; it defaults to `auth.uid()` at the database
--                level, and RLS is what actually keeps readers apart.
--   profiles   — the answers collected during onboarding (reading goal,
--                reading time, name, description). A blank row is
--                created automatically the moment a reader's account
--                exists (see the trigger below), so the app only ever
--                UPDATEs it, never has to decide between insert/upsert.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------- books
create table if not exists public.books (
  id              uuid primary key default gen_random_uuid(),
  google_books_id text not null unique,
  title           text not null,
  author          text not null default 'Unknown author',
  cover_url       text,
  page_count      integer check (page_count is null or page_count > 0),
  description     text,
  created_at      timestamptz not null default now()
);

-- Case-insensitive title lookups: BookCacheRepository.findByTitle uses
-- ILIKE with an exact pattern first, then a 'title%' prefix pattern.
create index if not exists books_title_lower_idx
  on public.books (lower(title) text_pattern_ops);

-- ----------------------------------------------------------- user_books
create table if not exists public.user_books (
  id           uuid primary key default gen_random_uuid(),
  -- Never set by the app — the column default resolves it from the
  -- request's JWT, so UserBookRepository never has to know or pass the
  -- current user's id. RLS below is what actually enforces ownership;
  -- this default just saves every insert from having to supply it.
  user_id      uuid not null default auth.uid()
                 references auth.users (id) on delete cascade,
  book_id      uuid not null references public.books (id) on delete cascade,
  current_page integer not null default 0 check (current_page >= 0),
  status       text not null default 'reading'
                 check (status in ('reading', 'finished')),
  -- Half-star granularity (`rate <book> 4.5`); null until rated. Only
  -- ever set once `status = 'finished'` — LibraryController.rateBook
  -- enforces that, not this column, so the same rule is easy to relax
  -- later without a migration.
  rating       numeric(2, 1) check (rating is null or (rating > 0 and rating <= 5)),
  started_at   timestamptz not null default now(),
  finished_at  timestamptz,
  updated_at   timestamptz not null default now(),
  -- One shelf entry per book *per reader* — this used to be a bare
  -- unique(book_id), which only worked while every row belonged to the
  -- same single local reader.
  unique (user_id, book_id)
);

-- Re-running this file against a database that already has `user_books`
-- (created before `rating`/`user_id` existed) needs explicit ALTERs —
-- `create table if not exists` won't touch an existing table.
alter table public.user_books add column if not exists rating numeric(2, 1);
alter table public.user_books drop constraint if exists user_books_rating_check;
alter table public.user_books add constraint user_books_rating_check
  check (rating is null or (rating > 0 and rating <= 5));

alter table public.user_books add column if not exists user_id uuid
  references auth.users (id) on delete cascade;
alter table public.user_books alter column user_id set default auth.uid();
-- Existing rows predate auth and have no real owner — wiped rather than
-- backfilled to some placeholder user, per the "start clean" call made
-- when multi-user support was added.
truncate table public.user_books;
alter table public.user_books alter column user_id set not null;
alter table public.user_books drop constraint if exists user_books_book_id_key;
alter table public.user_books drop constraint if exists user_books_user_id_book_id_key;
alter table public.user_books add constraint user_books_user_id_book_id_key
  unique (user_id, book_id);

create index if not exists user_books_updated_at_idx
  on public.user_books (updated_at desc);
create index if not exists user_books_user_id_idx
  on public.user_books (user_id);

-- --------------------------------------------------------------- policies
-- `books` is the shared Google Books cache — every signed-in reader
-- (anonymous or not) can read and write it, since caching a volume one
-- reader looked up benefits the next reader who searches for it too.
-- `user_books` is private per reader: each policy checks the row's
-- `user_id` against the caller's own `auth.uid()`.
--
-- Both are `to authenticated` rather than `to anon` — Supabase's
-- anonymous sign-in still issues a real session with role
-- `authenticated` (just with `is_anonymous: true`), so this covers
-- anonymous readers too. It closes the previous hole where the bare
-- anon key, with no session at all, could read/write everything.
alter table public.books      enable row level security;
alter table public.user_books enable row level security;

drop policy if exists "books: anon full access" on public.books;
drop policy if exists "books: authenticated full access" on public.books;
create policy "books: authenticated full access"
  on public.books for all
  to authenticated
  using (true) with check (true);

drop policy if exists "user_books: anon full access" on public.user_books;
drop policy if exists "user_books: select own" on public.user_books;
drop policy if exists "user_books: insert own" on public.user_books;
drop policy if exists "user_books: update own" on public.user_books;
drop policy if exists "user_books: delete own" on public.user_books;

create policy "user_books: select own"
  on public.user_books for select
  to authenticated
  using (auth.uid() = user_id);

create policy "user_books: insert own"
  on public.user_books for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "user_books: update own"
  on public.user_books for update
  to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "user_books: delete own"
  on public.user_books for delete
  to authenticated
  using (auth.uid() = user_id);

-- -------------------------------------------------------------- profiles
create table if not exists public.profiles (
  id                      uuid primary key references auth.users (id) on delete cascade,
  name                    text,
  description             text,
  reading_goal            integer check (reading_goal is null or reading_goal > 0),
  reading_minutes_per_day integer check (reading_minutes_per_day is null or reading_minutes_per_day > 0),
  created_at              timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles: select own" on public.profiles;
drop policy if exists "profiles: update own" on public.profiles;

create policy "profiles: select own"
  on public.profiles for select
  to authenticated
  using (auth.uid() = id);

create policy "profiles: update own"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

-- Creates the blank profile row the moment a reader's auth.users row
-- appears — passwordless email OTP (`signInWithOtp`/`verifyOTP`)
-- provisions that row on first verification, same as any other sign-up
-- method would, so this fires for every new reader. `security definer`
-- because the auth server's own role, not `authenticated`, is what
-- fires this trigger.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Q1/Q2 show this back before the reader has an account of their own,
-- so it can't rely on the `profiles: select own` policy above — this
-- is `security definer` instead, and only ever returns the two
-- averages, never a row, so it can't be used to read anyone's answers.
create or replace function public.onboarding_averages()
returns table (avg_reading_goal numeric, avg_reading_minutes numeric)
language sql
security definer
set search_path = public
stable
as $$
  select avg(reading_goal), avg(reading_minutes_per_day) from public.profiles;
$$;

grant execute on function public.onboarding_averages() to anon, authenticated;
