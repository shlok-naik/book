-- Lets a reader unmake a shelf, tag or series they made — the "+" panel's
-- own X on each chip. `shelves`/`tags`/`series` never got a delete policy
-- when they were created (`20260916000000_standalone_collections.sql`,
-- `20260917000000_local_series.sql`): only make-first, apply-after, never
-- undo the making. The composite foreign keys already do the right thing
-- once a row can be deleted at all — `on delete set null` on
-- `user_books.shelf_id`/`series_id` (a book falls back to its status
-- section, or out of the series, untouched otherwise), `on delete cascade`
-- on `book_tags.tag_id` (its link rows go with it).

drop policy if exists "shelves: delete own" on public.shelves;
create policy "shelves: delete own"
  on public.shelves for delete to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "tags: delete own" on public.tags;
create policy "tags: delete own"
  on public.tags for delete to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "series: delete own" on public.series;
create policy "series: delete own"
  on public.series for delete to authenticated
  using ((select auth.uid()) = user_id);
