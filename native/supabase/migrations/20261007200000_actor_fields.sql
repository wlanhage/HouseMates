-- Vem som skapade något och vem som gjorde det går inte att ändra från appen, inte heller med
-- en ändring som rör något annat. Bara servern sätter dem.

create or replace function public.tg_todos_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.title := trim(new.title);
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
    new.done_by := case when new.done then new.created_by end;
    new.done_at := case when new.done then now() end;
    return new;
  end if;
  new.created_by := old.created_by;
  if new.done and not old.done then
    new.done_by := coalesce(auth.uid(), new.done_by);
    new.done_at := now();
  elsif not new.done and old.done then
    new.done_by := null;
    new.done_at := null;
  else
    new.done_by := old.done_by;
    new.done_at := old.done_at;
  end if;
  return new;
end $$;

-- En senare "senast gjord" än förut är en avbockning: den inloggade gjorde den, och aldrig i
-- framtiden. Ett tidigare datum (rätta) behåller den som gjorde den, och inget datum (ångra)
-- tar bort den.
create or replace function public.tg_chores_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.title := trim(new.title);
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
    new.last_done_at := null;
    new.last_done_by := null;
    return new;
  end if;
  new.created_by := old.created_by;
  if new.last_done_at > coalesce(old.last_done_at, '-infinity'::timestamptz) then
    new.last_done_at := least(new.last_done_at, now());
    new.last_done_by := coalesce(auth.uid(), new.last_done_by);
  elsif new.last_done_at is null then
    new.last_done_by := null;
  elsif new.last_done_at is distinct from old.last_done_at then
    new.last_done_by := coalesce(old.last_done_by, auth.uid(), new.last_done_by);
  else
    new.last_done_by := old.last_done_by;
  end if;
  return new;
end $$;
