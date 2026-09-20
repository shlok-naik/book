-- Reader-authored notes about how a book made them feel — "loved the
-- ending", "the middle dragged" — captured by cactus pro's
-- natural-language mode (a `remember <book> :: <note>` line the
-- `parse-command` edge function extracts alongside its five shelf
-- commands) and fed back into that same function as grounding for the
-- `recommend` command.
--
-- Private per reader, same shape as `user_books`/`reading_events`: RLS
-- scopes every row to its own `user_id`, defaulted at the database
-- level rather than trusted from the client (see
-- `20260821000000_harden_rls_and_indexes.sql` for why `(select
-- auth.uid())` rather than the bare function call).

create table if not exists public.memories (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  -- Nullable: most memories name the book they're about, but the
  -- command grammar doesn't force one — "I always end up disappointed
  -- by hyped-up fantasy" is a real preference with nothing to attach a
  -- title to.
  book_title text,
  note       text not null,
  created_at timestamptz not null default now()
);

create index if not exists memories_user_id_created_at_idx
  on public.memories (user_id, created_at desc);

alter table public.memories enable row level security;

create policy "memories: select own"
  on public.memories for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "memories: insert own"
  on public.memories for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "memories: delete own"
  on public.memories for delete
  to authenticated
  using ((select auth.uid()) = user_id);
