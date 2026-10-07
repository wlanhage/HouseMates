-- Vem en kalenderhändelse är för, så att båda telefonerna visar samma färg. Händelsen finns
-- bara i telefonerna (EventKit); här sparas bara dess UID och personen. Ingen rad betyder
-- gemensamt. Raden tas bort (mjukt) när händelsen raderas i appen.
create table public.event_assignees (
  id           uuid primary key,             -- klientgenererat (offline-idempotens)
  household_id uuid not null default public.my_household_id()
               references public.households(id) on delete cascade,
  event_uid    text not null check (char_length(event_uid) between 1 and 200),
  assignee     uuid references auth.users(id) on delete set null,   -- null = gemensamt
  created_at   timestamptz not null default now(),
  deleted_at   timestamptz
);
-- En person per händelse; försöker båda sätta den samtidigt vinner den som hann först.
create unique index event_assignees_uid on public.event_assignees (household_id, event_uid)
  where deleted_at is null;

alter table public.event_assignees enable row level security;
create policy event_assignees_member on public.event_assignees for all
  using (household_id = public.my_household_id())
  with check (household_id = public.my_household_id());

alter publication supabase_realtime add table public.event_assignees;
