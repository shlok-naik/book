-- Adds a "did not finish" shelf status and its own reading-event type,
-- for `add <book> dnf` — no reason captured, just a shelf a dropped
-- book lands on instead of staying in "reading" or getting deleted.
alter table public.user_books
  drop constraint if exists user_books_status_check,
  add constraint user_books_status_check
    check (status in ('to_be_read', 'reading', 'finished', 'dnf'));

alter table public.reading_events
  drop constraint if exists reading_events_action_check,
  add constraint reading_events_action_check
    check (
      action in (
        'start', 'update', 'finish', 'rate', 'delete', 'add_to_be_read', 'dnf'
      )
    );
