-- Att göra och städ, med "för vem" och en färg per person (som i webbappen: blå och rosa,
-- grönt är gemensamt och sätts i appen).

-- ── Färg per person ──────────────────────────────────────────
alter table public.profiles add column color text not null default '#378ADD'
  check (color ~ '^#[0-9A-Fa-f]{6}$');

-- Befintliga hushåll: den som gick med sist blir rosa.
update public.profiles p set color = '#D4537E'
from public.household_members m
where m.user_id = p.id
  and m.joined_at > (select min(joined_at) from public.household_members o where o.household_id = m.household_id);

create or replace function public.create_household() returns public.households
language plpgsql security definer set search_path = public as $$
declare h households;
begin
  if auth.uid() is null then raise exception 'Du är inte inloggad'; end if;
  if my_household_id() is not null then raise exception 'Du är redan med i ett hushåll'; end if;
  insert into households (invite_code) values (new_invite_code()) returning * into h;
  insert into household_members (household_id, user_id) values (h.id, auth.uid());
  update profiles set color = '#378ADD' where id = auth.uid();
  return h;
end $$;

create or replace function public.join_household(p_code text) returns public.households
language plpgsql security definer set search_path = public as $$
declare h households;
begin
  if auth.uid() is null then raise exception 'Du är inte inloggad'; end if;
  if my_household_id() is not null then raise exception 'Du är redan med i ett hushåll'; end if;
  -- Låset hindrar att två personer går med samtidigt och gör hushållet större än två.
  select * into h from households where invite_code = upper(trim(p_code)) for update;
  if h.id is null then raise exception 'Hittade inget hushåll med den koden'; end if;
  if (select count(*) from household_members where household_id = h.id) >= 2 then
    raise exception 'Hushållet har redan två medlemmar';
  end if;
  insert into household_members (household_id, user_id) values (h.id, auth.uid());
  -- Partnerns färg finns redan; den som går med får den andra.
  update profiles set color = case
    when exists (
      select 1 from household_members m join profiles p on p.id = m.user_id
      where m.household_id = h.id and m.user_id <> auth.uid() and p.color = '#378ADD'
    ) then '#D4537E' else '#378ADD' end
  where id = auth.uid();
  return h;
end $$;

-- ── Att göra ─────────────────────────────────────────────────
create table public.todos (
  id           uuid primary key,             -- klientgenererat (offline-idempotens)
  household_id uuid not null default public.my_household_id()
               references public.households(id) on delete cascade,
  title        text not null check (char_length(trim(title)) between 1 and 200),
  assignee     uuid references auth.users(id) on delete set null,   -- null = gemensamt
  start_date   date,                         -- period: "gör inom start–due"
  due_date     date,
  done         boolean not null default false,
  done_by      uuid references auth.users(id) on delete set null,
  done_at      timestamptz,
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  deleted_at   timestamptz,
  check (start_date is null or (due_date is not null and start_date <= due_date))
);
create index todos_by_household on public.todos (household_id, created_at) where deleted_at is null;

create or replace function public.tg_todos_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.title := trim(new.title);
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
    new.done_by := case when new.done then new.created_by end;
    new.done_at := case when new.done then now() end;
  elsif new.done and not old.done then
    new.done_by := coalesce(auth.uid(), new.done_by);
    new.done_at := now();
  elsif not new.done and old.done then
    new.done_by := null;
    new.done_at := null;
  end if;
  return new;
end $$;
create trigger todos_before before insert or update on public.todos
  for each row execute function public.tg_todos_before();

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
create trigger todos_activity after insert or update on public.todos
  for each row execute function public.tg_todos_activity();

-- ── Städ ─────────────────────────────────────────────────────
-- Återkommande sysslor: att bocka av sätter last_done_*, raden försvinner inte.
create table public.chores (
  id            uuid primary key,
  household_id  uuid not null default public.my_household_id()
                references public.households(id) on delete cascade,
  title         text not null check (char_length(trim(title)) between 1 and 200),
  assignee      uuid references auth.users(id) on delete set null,  -- null = gemensamt
  interval_days int check (interval_days is null or interval_days between 1 and 365),
  last_done_at  timestamptz,
  last_done_by  uuid references auth.users(id) on delete set null,
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index chores_by_household on public.chores (household_id, created_at) where deleted_at is null;

-- En senare "senast gjord" än förut är en avbockning: den inloggade gjorde den, och aldrig i
-- framtiden. En tidigare (ångra eller rätta datumet) släpps igenom som klienten skickade den.
create or replace function public.tg_chores_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.title := trim(new.title);
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
    new.last_done_at := null;
    new.last_done_by := null;
  elsif new.last_done_at > coalesce(old.last_done_at, '-infinity'::timestamptz) then
    new.last_done_at := least(new.last_done_at, now());
    new.last_done_by := coalesce(auth.uid(), new.last_done_by);
  end if;
  return new;
end $$;
create trigger chores_before before insert or update on public.chores
  for each row execute function public.tg_chores_before();

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
  elsif new.last_done_at > coalesce(old.last_done_at, '-infinity'::timestamptz) then
    kind := 'chore.done';
  end if;
  if kind is not null and actor is not null then
    insert into activity_log (household_id, actor, type, entity_id, payload)
    values (new.household_id, actor, kind, new.id::text, jsonb_build_object('title', new.title));
  end if;
  return new;
end $$;
create trigger chores_activity after insert or update on public.chores
  for each row execute function public.tg_chores_activity();

-- ── Behörigheter och realtid ─────────────────────────────────
alter table public.todos enable row level security;
alter table public.chores enable row level security;

create policy todos_member on public.todos for all
  using (household_id = public.my_household_id())
  with check (household_id = public.my_household_id());
create policy chores_member on public.chores for all
  using (household_id = public.my_household_id())
  with check (household_id = public.my_household_id());

alter publication supabase_realtime add table public.todos, public.chores;
