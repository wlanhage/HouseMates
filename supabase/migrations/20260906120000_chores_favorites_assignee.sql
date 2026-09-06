-- Användarbeslut 2026-09-06 (utanför spec v1 §17): städsysslor med
-- "senast gjort", favoritmiddagar och färgkod efter vem något är för.

-- ── Events: "för vem" (färgkod) ──────────────────────────────
-- username | 'both' | null. null = saknar markering (t.ex. skapat i Apple
-- Kalender) och visas som gemensamt. Speglas i ICS som X-PLANERAREN-FOR.
alter table public.events add column assignee text;

-- ── Städsysslor ──────────────────────────────────────────────
-- Återkommande: att bocka av sätter last_done_*; raden försvinner inte.
create table public.chores (
  id           uuid primary key,
  title        text not null,
  assignee     text,                      -- username | 'both' | null
  last_done_at timestamptz,
  last_done_by text references public.profiles(username),
  created_by   text not null references public.profiles(username),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  version      int not null default 1,
  deleted_at   timestamptz,
  deleted_by   text references public.profiles(username)
);

-- Samma version-bump som todos.
create trigger chores_before before insert or update on public.chores
  for each row execute function public.tg_todos_before();

-- Aktörsfält tvingas server-side. En "framåt"-ändring av last_done_at
-- (nyare än förut) är en avbockning; en bakåt-ändring är ångra och släpps
-- igenom som den är.
create or replace function public.tg_chores_actor_fields() returns trigger
language plpgsql security definer set search_path = public as $$
declare me text := my_username();
begin
  if me is not null then
    if tg_op = 'INSERT' then new.created_by := me; end if;
    if tg_op = 'UPDATE'
       and new.last_done_at > coalesce(old.last_done_at, '-infinity'::timestamptz) then
      new.last_done_by := me; new.last_done_at := now();
    end if;
    if tg_op = 'UPDATE' and new.deleted_at is not null and old.deleted_at is null then
      new.deleted_by := me;
    end if;
  end if;
  return new;
end $$;
create trigger chores_actor before insert or update on public.chores
  for each row execute function public.tg_chores_actor_fields();

create or replace function public.tg_chores_activity() returns trigger
language plpgsql security definer set search_path = public as $$
declare actor text := coalesce(my_username(), new.created_by);
begin
  if tg_op = 'INSERT' then
    insert into activity_log(type, actor, entity_type, entity_id, payload)
    values ('chore.created', actor, 'chore', new.id::text, jsonb_build_object('title', new.title));
  elsif tg_op = 'UPDATE' then
    if new.deleted_at is not null and old.deleted_at is null then
      insert into activity_log(type, actor, entity_type, entity_id, payload)
      values ('chore.deleted', actor, 'chore', new.id::text, jsonb_build_object('title', new.title));
    elsif new.deleted_at is null and old.deleted_at is not null then
      insert into activity_log(type, actor, entity_type, entity_id, payload)
      values ('chore.restored', actor, 'chore', new.id::text, jsonb_build_object('title', new.title));
    elsif new.last_done_at > coalesce(old.last_done_at, '-infinity'::timestamptz) then
      insert into activity_log(type, actor, entity_type, entity_id, payload)
      values ('chore.done', actor, 'chore', new.id::text, jsonb_build_object('title', new.title));
    end if;
  end if;
  return new;
end $$;
create trigger chores_activity after insert or update on public.chores
  for each row execute function public.tg_chores_activity();

-- ── Favoritmiddagar ──────────────────────────────────────────
create table public.favorites (
  id         uuid primary key,
  name       text not null,
  items      text[] not null default '{}',
  created_by text not null references public.profiles(username),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create or replace function public.tg_favorites_actor_fields() returns trigger
language plpgsql security definer set search_path = public as $$
declare me text := my_username();
begin
  if tg_op = 'INSERT' and me is not null then new.created_by := me; end if;
  return new;
end $$;
create trigger favorites_actor before insert on public.favorites
  for each row execute function public.tg_favorites_actor_fields();

-- ── RLS + realtime ───────────────────────────────────────────
alter table public.chores    enable row level security;
alter table public.favorites enable row level security;
create policy chores_member_all on public.chores
  for all using (public.is_member()) with check (public.is_member());
create policy favorites_member_all on public.favorites
  for all using (public.is_member()) with check (public.is_member());

alter publication supabase_realtime add table public.chores, public.favorites;
