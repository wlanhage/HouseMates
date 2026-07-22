-- Autocomplete ur inköpshistoriken (motsvarar gamla /api/shopping/suggest).
create or replace function public.suggest_shopping(q text default '')
returns table (name text)
language sql stable security definer set search_path = public as $$
  select s.name
  from shopping_items s
  where public.is_member()
    and (q = '' or s.name_norm like lower(trim(q)) || '%')
  group by s.name_norm, s.name
  order by count(*) desc, max(s.created_at) desc
  limit 8
$$;
