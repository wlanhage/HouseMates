-- Ångra, som i webbappen. En borttagen rad tas tillbaka med deleted_at = null, och en avbockad
-- städsyssla får tillbaka sitt förra datum och den som gjorde den. Båda loggas, så att
-- notisdigesten (digest.ts) nettar bort det som ångrades i stället för att berätta det för
-- partnern.

create or replace function public.tg_shopping_activity() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  actor uuid := coalesce(auth.uid(), new.created_by);
  kind text;
begin
  if tg_op = 'INSERT' then
    kind := 'shopping.added';
  elsif new.deleted_at is not null and old.deleted_at is null then
    -- Att tömma bockade varor är städning, inget partnern behöver en notis om.
    kind := case when old.checked then null else 'shopping.deleted' end;
  elsif new.deleted_at is null and old.deleted_at is not null then
    kind := case when old.checked then null else 'shopping.restored' end;
  elsif new.checked and not old.checked then
    kind := 'shopping.checked';
  elsif not new.checked and old.checked then
    kind := 'shopping.unchecked';
  end if;
  if kind is not null and actor is not null then
    insert into activity_log (household_id, actor, type, entity_id, payload)
    values (new.household_id, actor, kind, new.id::text, jsonb_build_object('name', new.name));
  end if;
  return new;
end $$;

create or replace function public.tg_todos_activity() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  actor uuid := coalesce(auth.uid(), new.created_by);
  kind text;
begin
  if tg_op = 'INSERT' then
    kind := 'todo.created';
  elsif new.deleted_at is not null and old.deleted_at is null then
    -- Att rensa klara uppgifter är städning, inget partnern behöver en notis om.
    kind := case when old.done then null else 'todo.deleted' end;
  elsif new.deleted_at is null and old.deleted_at is not null then
    kind := case when old.done then null else 'todo.restored' end;
  elsif new.done and not old.done then
    kind := 'todo.done';
  elsif not new.done and old.done then
    kind := 'todo.undone';
  end if;
  if kind is not null and actor is not null then
    insert into activity_log (household_id, actor, type, entity_id, payload)
    values (new.household_id, actor, kind, new.id::text, jsonb_build_object('title', new.title));
  end if;
  return new;
end $$;

create or replace function public.tg_chores_activity() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  actor uuid := coalesce(auth.uid(), new.created_by);
  kind text;
begin
  if tg_op = 'INSERT' then
    kind := 'chore.created';
  elsif new.deleted_at is not null and old.deleted_at is null then
    kind := 'chore.deleted';
  elsif new.deleted_at is null and old.deleted_at is not null then
    kind := 'chore.restored';
  elsif new.last_done_at > coalesce(old.last_done_at, '-infinity'::timestamptz) then
    kind := 'chore.done';
  elsif new.last_done_at is distinct from old.last_done_at then
    kind := 'chore.undone';
  end if;
  if kind is not null and actor is not null then
    insert into activity_log (household_id, actor, type, entity_id, payload)
    values (new.household_id, actor, kind, new.id::text, jsonb_build_object('title', new.title));
  end if;
  return new;
end $$;

-- Ett tidigare datum (ångra eller rätta) får peka ut vem i hushållet som helst som den som gjorde
-- sysslan, så att ångra kan ge tillbaka partnerns förra avbockning. Någon utanför hushållet går
-- aldrig att ange.
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
  new.created_by := case when new.created_by is null then null else old.created_by end;
  if new.last_done_at > coalesce(old.last_done_at, '-infinity'::timestamptz) then
    new.last_done_at := least(new.last_done_at, now());
    new.last_done_by := coalesce(auth.uid(), new.last_done_by);
  elsif new.last_done_at is null then
    new.last_done_by := null;
  elsif new.last_done_at is distinct from old.last_done_at then
    new.last_done_by := case
      when exists (select 1 from household_members m
                   where m.household_id = new.household_id and m.user_id = new.last_done_by)
        then new.last_done_by
      else coalesce(old.last_done_by, auth.uid())
    end;
  elsif new.last_done_by is not null then
    new.last_done_by := old.last_done_by;
  end if;
  return new;
end $$;
