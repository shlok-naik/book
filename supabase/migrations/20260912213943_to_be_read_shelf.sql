-- Adds a "to be read" shelf status and its own reading-event type, for
-- `add <book> tbr` / `add <book> finished` — putting a title straight
-- onto a shelf without going through `start`. `add <book> finished`
-- logs as the existing `finish` event (that's exactly what happened);
-- `add <book> tbr` gets a new `add_to_be_read` one since nothing else
-- fits.
alter table public.user_books
  drop constraint if exists user_books_status_check,
  add constraint user_books_status_check
    check (status in ('to_be_read', 'reading', 'finished'));

alter table public.reading_events
  drop constraint if exists reading_events_action_check,
  add constraint reading_events_action_check
    check (
      action in ('start', 'update', 'finish', 'rate', 'delete', 'add_to_be_read')
    );
