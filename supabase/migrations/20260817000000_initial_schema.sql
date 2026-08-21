-- Baseline schema for the library, streaks and onboarding features.
--
-- This file records the shape the database already had when migration
-- history was introduced; it is written idempotently (`create ... if not
-- exists`, `create or replace`) so applying it to the existing project
-- is a no-op, and applying it to a fresh project brings it up to the
-- same baseline. Everything after this point lives in its own numbered
-- migration — never edit this file to change the schema.
--
-- Tables:
--   books          — shared cache of Google Books volumes, keyed for
--                    de-duplication on `google_books_id`. Not owned by
--                    any one reader: caching a volume one reader looked
--                    up benefits the next reader who searches for it.
--   user_books     — a reader's progress against a cached book. `user_id`
--                    is never set by the app; it defaults to `auth.uid()`
--                    at the database level and RLS is what actually keeps
--                    readers apart.
--   reading_events — one row per shelf command that took effect, which
--                    the streaks page groups by local day.
--   profiles       — the answers collected during onboarding. A blank row
--                    is created by trigger the moment a reader's account
--                    exists, so the app only ever UPDATEs it.

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
  user_id      uuid not null default auth.uid()
                 references auth.users (id) on delete cascade,
  book_id      uuid not null references public.books (id) on delete cascade,
  current_page integer not null default 0 check (current_page >= 0),
  status       text not null default 'reading'
                 check (status in ('reading', 'finished')),
  -- Half-star granularity (`rate <book> 4.5`); null until rated. Only
  -- ever set once `status = 'finished'` — LibraryController.rateBook
  -- enforces that, not this column, so the rule is easy to relax later
  -- without a migration.
  rating       numeric(2, 1) check (rating is null or (rating > 0 and rating <= 5)),
  started_at   timestamptz not null default now(),
  finished_at  timestamptz,
  updated_at   timestamptz not null default now(),
  -- One shelf entry per book *per reader*.
  unique (user_id, book_id)
);

create index if not exists user_books_updated_at_idx
  on public.user_books (updated_at desc);
create index if not exists user_books_user_id_idx
  on public.user_books (user_id);

-- --------------------------------------------------------- reading_events
create table if not exists public.reading_events (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid()
                references auth.users (id) on delete cascade,
  action      text not null
                check (action in ('start', 'update', 'finish', 'rate', 'delete')),
  -- The book the command was about, so the day-detail sheet can read
  -- "started Dune" rather than just "started". Deliberately not a
  -- `book_id` reference: the event should still read fine after the book
  -- itself is deleted from the shelf.
  title       text,
  occurred_at timestamptz not null default now()
);

create index if not exists reading_events_user_id_occurred_at_idx
  on public.reading_events (user_id, occurred_at);

-- -------------------------------------------------------------- profiles
create table if not exists public.profiles (
  id                      uuid primary key references auth.users (id) on delete cascade,
  name                    text,
  description             text,
  reading_goal            integer check (reading_goal is null or reading_goal > 0),
  reading_minutes_per_day integer check (reading_minutes_per_day is null or reading_minutes_per_day > 0),
  created_at              timestamptz not null default now()
);

-- ------------------------------------------------------------ row level
alter table public.books          enable row level security;
alter table public.user_books     enable row level security;
alter table public.reading_events enable row level security;
alter table public.profiles       enable row level security;

-- ------------------------------------------------------------- triggers
-- Creates the blank profile row the moment a reader's auth.users row
-- appears — passwordless email OTP provisions that row on first
-- verification, same as any other sign-up method would. `security
-- definer` because the auth server's own role, not `authenticated`, is
-- what fires this trigger.
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

-- Onboarding Q1/Q2 show these averages back before the reader has an
-- account of their own, so this can't rely on the `profiles: select own`
-- policy. `security definer` instead, returning only the two aggregates
-- and never a row, so it cannot be used to read anyone's answers.
create or replace function public.onboarding_averages()
returns table (avg_reading_goal numeric, avg_reading_minutes numeric)
language sql
security definer
set search_path = public
stable
as $$
  select avg(reading_goal), avg(reading_minutes_per_day) from public.profiles;
$$;
