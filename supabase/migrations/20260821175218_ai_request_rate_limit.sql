-- Per-reader rate limiting for the `parse-command` edge function.
--
-- The function holds the Groq API key, so the app no longer ships it —
-- but that only moves the abuse surface rather than closing it: anyone
-- with an (anonymous) account could otherwise call the endpoint in a
-- loop and spend the project's whole Groq quota. This gives the function
-- a counter it can check before it forwards anything upstream.
--
-- `ai_requests` deliberately has RLS enabled and *no policies at all*.
-- That is not an oversight — it means no client can read, insert into, or
-- delete from it directly, so the ledger can only ever be touched by
-- `claim_ai_request()` below, which runs as the definer. A reader cannot
-- clear their own history to reset their limit.

create table if not exists public.ai_requests (
  id           bigint generated always as identity primary key,
  user_id      uuid not null default auth.uid()
                 references auth.users (id) on delete cascade,
  requested_at timestamptz not null default now()
);

create index if not exists ai_requests_user_id_requested_at_idx
  on public.ai_requests (user_id, requested_at desc);
create index if not exists ai_requests_requested_at_idx
  on public.ai_requests (requested_at);

alter table public.ai_requests enable row level security;

-- Records one AI request against the caller and reports whether they
-- were still under their allowance. Returns false rather than raising,
-- so the edge function can answer with a friendly 429 instead of a
-- generic failure.
--
-- The window and the ceiling are constants inside the body on purpose.
-- As parameters they would be trivially defeated — this function is
-- reachable over PostgREST as `/rest/v1/rpc/claim_ai_request`, so any
-- caller could simply ask for a limit of a million.
create or replace function public.claim_ai_request()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  -- 60 natural-language parses per rolling hour. Comfortably above what
  -- a reader logging their books can produce by hand, low enough that a
  -- script cannot run up a bill before it trips.
  request_limit  constant integer  := 60;
  request_window constant interval := interval '1 hour';
  uid            uuid := auth.uid();
  used           integer;
begin
  if uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- Opportunistic housekeeping: the ledger only needs the current
  -- window, so old rows are dead weight. Done on roughly one call in a
  -- hundred rather than every call, since the scan is not worth paying
  -- for on the hot path.
  if random() < 0.01 then
    delete from public.ai_requests
      where requested_at < now() - interval '2 days';
  end if;

  select count(*) into used
    from public.ai_requests
   where user_id = uid
     and requested_at > now() - request_window;

  if used >= request_limit then
    return false;
  end if;

  insert into public.ai_requests (user_id) values (uid);
  return true;
end;
$$;

revoke execute on function public.claim_ai_request() from public, anon;
grant execute on function public.claim_ai_request() to authenticated;
