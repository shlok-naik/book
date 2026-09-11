-- A profile picture for the settings screen's membership card. No name
-- field goes with it — the card is deliberately just a photo and the
-- email `linkEmail` already attaches, nothing new to type.
alter table public.profiles
  add column if not exists avatar_url text;

-- Public bucket: avatar URLs are shown straight from `Image.network`
-- with no signed-URL round trip, the same way `books.cover_url` (Google
-- Books' own CDN) already works. Nothing sensitive lives in a profile
-- picture, so this trades a harder-to-guess URL for one that just works.
insert into storage.buckets (id, name, public)
  values ('avatars', 'avatars', true)
  on conflict (id) do nothing;

-- One reader, one object, at `<uid>/avatar` — the folder *is* the
-- ownership check, so every policy below just compares the path's first
-- segment to `auth.uid()` rather than needing a join back to `profiles`.
drop policy if exists "avatars: public read" on storage.objects;
drop policy if exists "avatars: owner insert" on storage.objects;
drop policy if exists "avatars: owner update" on storage.objects;
drop policy if exists "avatars: owner delete" on storage.objects;

create policy "avatars: public read"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "avatars: owner insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (select auth.uid())::text = (storage.foldername(name))[1]
  );

create policy "avatars: owner update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (select auth.uid())::text = (storage.foldername(name))[1]
  );

create policy "avatars: owner delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (select auth.uid())::text = (storage.foldername(name))[1]
  );
