-- Förslag medan man skriver en vara, som webbappens suggest_shopping: tidigare tillagda varor som
-- börjar på det man skrivit, de vanligaste först. Historiken är activity_log (90 dagar), eftersom
-- rensade varor raderas efter 30 dagar. Det som redan står obockat på listan föreslås inte.
create or replace function public.suggest_shopping(q text default '')
returns table (name text)
language sql stable security definer set search_path = public as $$
  select (array_agg(a.payload->>'name' order by a.id desc))[1]
  from activity_log a
  where a.household_id = my_household_id()
    and a.type = 'shopping.added'
    and starts_with(lower(a.payload->>'name'), lower(trim(q)))
    and not exists (
      select 1 from shopping_items s
      where s.household_id = a.household_id
        and s.name_norm = lower(a.payload->>'name')
        and not s.checked
        and s.deleted_at is null
    )
  group by lower(a.payload->>'name')
  order by count(*) desc, max(a.id) desc
  limit 8
$$;

-- Nya funktioner får annars EXECUTE för alla (se 20261008090000_hardening.sql).
revoke execute on function public.suggest_shopping(text) from public, anon;
