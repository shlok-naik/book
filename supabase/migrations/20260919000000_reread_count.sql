-- Adds re-read tracking for `restart <book> [date]` — a finished book put
-- back on the reading shelf for another pass. `reread_count` is bumped
-- once per restart, driving a bronze/silver/gold cover badge client-side.
alter table public.user_books
  add column if not exists reread_count int not null default 0
    check (reread_count >= 0);

alter table public.reading_events
  drop constraint if exists reading_events_action_check,
  add constraint reading_events_action_check
    check (
      action in (
        'start', 'update', 'finish', 'rate', 'delete', 'add_to_be_read',
        'dnf', 'restart'
      )
    );
