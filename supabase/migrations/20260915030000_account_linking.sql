-- Linking an email that already belongs to another reader's library.
--
-- Every install starts on its own anonymous account. Linking an email in
-- settings attaches it to that account. A *second* device that tries to
-- link the same email can't — the address is taken — so it signs in to the
-- email's account instead, and the reader picks which of the two libraries
-- to keep: the one already on the email account, or the one on this device.
-- The other is discarded for good (the reader confirms that first).
--
-- The email account's user id always survives, whichever library is kept:
-- it is what the email, the RevenueCat purchaser and every other device
-- signed in to that email are attached to. Keeping "this device's library"
-- therefore means moving this device's rows onto that id.
--
-- 1. `profiles.device_name` / `last_seen_at` — written by the app at
--    startup, so the choice can say "Pixel 8 · last used 9.12.26" rather
--    than two anonymous numbers.
-- 2. `library_summary()` — what each option shows, for the caller's own
--    account.
-- 3. `adopt_library(from, to)` — the move, run only by the `link-account`
--    edge function with the service role after it has verified the caller
--    holds both accounts. Not callable by readers at all.

-- ------------------------------------------------------------ 1. profile
alter table public.profiles
  add column if not exists device_name  text
    check (device_name is null or char_length(device_name) <= 80),
  add column if not exists last_seen_at timestamptz;

-- --------------------------------------------------------- 2. summary
create or replace function public.library_summary()
returns table (
  book_count   integer,
  memory_count integer,
  event_count  integer,
  created_at   timestamptz,
  device_name  text,
  last_seen_at timestamptz
)
language sql
security invoker
stable
set search_path = public
as $$
  select
    (select count(*)::integer from public.user_books),
    (select count(*)::integer from public.memories),
    (select count(*)::integer from public.reading_events),
    p.created_at,
    p.device_name,
    p.last_seen_at
  from public.profiles p
  where p.id = (select auth.uid());
$$;

revoke execute on function public.library_summary() from public, anon;
grant execute on function public.library_summary() to authenticated;

-- ------------------------------------------------------------ 3. adopt
-- Moving a row to another owner is not the reader doing something with
-- the book, so it must not bump `updated_at` (which orders the shelf and
-- picks "currently reading"). The trigger already ignores position-only
-- writes; it now ignores owner changes too. Nothing else ever changes
-- `user_id` — RLS's `with check` forbids it for readers.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_table_name = 'user_books' then
    if new.status is distinct from old.status
       and new.shelf_position is not distinct from old.shelf_position then
      new.shelf_position = null;
    end if;
    if (to_jsonb(new) - 'shelf_position' - 'updated_at' - 'user_id')
       = (to_jsonb(old) - 'shelf_position' - 'updated_at' - 'user_id') then
      new.updated_at = old.updated_at;
      return new;
    end if;
  end if;
  -- Nested rather than `and`-ed: plpgsql doesn't guarantee short-circuit
  -- evaluation, and `new.body` doesn't exist on any other table.
  if tg_table_name = 'book_comments' then
    if new.body is not distinct from old.body then
      new.updated_at = old.updated_at;
      return new;
    end if;
  end if;
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.adopt_library(p_from uuid, p_to uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_from is null or p_to is null or p_from = p_to then
    raise exception 'two different accounts are required';
  end if;

  -- The kept library replaces whatever the email account had.
  delete from public.reading_events where user_id = p_to;
  delete from public.memories where user_id = p_to;
  delete from public.user_books where user_id = p_to;  -- cascades tags/comments

  update public.user_books     set user_id = p_to where user_id = p_from;
  update public.book_tags      set user_id = p_to where user_id = p_from;
  update public.book_comments  set user_id = p_to where user_id = p_from;
  update public.reading_events set user_id = p_to where user_id = p_from;
  update public.memories       set user_id = p_to where user_id = p_from;

  -- The goal travels with the library it was set against.
  update public.profiles to_profile
     set reading_goal = coalesce(from_profile.reading_goal, to_profile.reading_goal)
    from public.profiles from_profile
   where to_profile.id = p_to and from_profile.id = p_from;
end;
$$;

revoke execute on function public.adopt_library(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.adopt_library(uuid, uuid) to service_role;
