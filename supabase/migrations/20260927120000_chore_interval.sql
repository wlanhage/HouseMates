-- Städsysslor kan ha ett intervall (användarbeslut 2026-09-27): sista dag att
-- göra sysslan = senast gjord (annars skapad) + interval_days. Beräknas i
-- klienten; null = inget intervall.
alter table public.chores
  add column interval_days int check (interval_days is null or interval_days > 0);
