-- Schema for the library feature.
-- Run this once in the Supabase SQL editor (or as a migration).
--
-- Two tables:
--   books      — the shared cache of Google Books volumes. One row per
--                volume; `google_books_id` is the de-duplication key the
--                cache-first lookup upserts on.
--   user_books — the reader's progress against a cached book.
--
-- Authentication is out of scope for this feature, so `user_books` has
-- no owner column and RLS is left permissive for the anon key. Adding
-- auth later means: add `user_id uuid references auth.users`, filter on
-- it in UserBookRepository, and replace the policies below.

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
  book_id      uuid not null references public.books (id) on delete cascade,
  current_page integer not null default 0 check (current_page >= 0),
  status       text not null default 'reading'
                 check (status in ('reading', 'finished')),
  started_at   timestamptz not null default now(),
  finished_at  timestamptz,
  updated_at   timestamptz not null default now(),
  -- One shelf entry per book, which is what makes `start <book>`
  -- idempotent instead of piling up duplicates.
  unique (book_id)
);

create index if not exists user_books_updated_at_idx
  on public.user_books (updated_at desc);

-- --------------------------------------------------------------- policies
-- Permissive by design while auth is out of scope: the anon key is the
-- only caller. Tighten these the moment users exist.
alter table public.books      enable row level security;
alter table public.user_books enable row level security;

drop policy if exists "books: anon full access" on public.books;
create policy "books: anon full access"
  on public.books for all
  using (true) with check (true);

drop policy if exists "user_books: anon full access" on public.user_books;
create policy "user_books: anon full access"
  on public.user_books for all
  using (true) with check (true);
