-- ============================================================
-- Planeraren – Postgres-schema för Supabase
-- Översatt från db/schema.sql (SQLite). Nyckelidéer:
--  * profiles mappar auth.users(uuid) ↔ kort username ('anna')
--  * övriga tabeller använder username (text) precis som SQLite-
--    versionen → frontendens datamodell förblir oförändrad
--  * activity_log + notification_queue skrivs av SECURITY DEFINER-
--    triggers → mutation + logg + kö är atomärt, precis som förr
--  * version-bump och name_norm sätts av triggers (ej klienten)
--  * RLS: endast de två medlemmarna (raderna i profiles) har åtkomst
-- ============================================================

create extension if not exists pgcrypto;

-- ── Profiler ─────────────────────────────────────────────────
create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  username   text unique not null check (username ~ '^[a-z0-9_-]{2,20}$'),
  name       text not null,
  color      text not null,
  created_at timestamptz not null default now()
);

create or replace function public.is_member() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from profiles where id = auth.uid()) $$;

create or replace function public.my_username() returns text
language sql stable security definer set search_path = public as
$$ select username from profiles where id = auth.uid() $$;

-- ── CalDAV-konton (endast edge functions/service role) ───────
create table public.caldav_accounts (
  username      text primary key references public.profiles(username),
  apple_id      text not null,
  password_enc  text not null,          -- base64(iv‖tag‖ct), AES-256-GCM med edge-secret
  calendar_href text not null,
  updated_at    timestamptz not null default now()
);

-- ── Kalender-cache ───────────────────────────────────────────
create table public.events (
  id            uuid primary key default gen_random_uuid(),
  caldav_uid    text not null,
  recurrence_id text not null default '',
  caldav_href   text,
  etag          text,
  title         text not null,
  location      text,
  notes         text,
  all_day       boolean not null default false,
  start_ts      timestamptz,
  end_ts        timestamptz,
  start_date    date,
  end_date      date,                    -- exklusivt
  created_by    text references public.profiles(username),
  raw_ics       text,
  synced_at     timestamptz,
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  deleted_by    text references public.profiles(username),
  check (
    (all_day = false and start_ts is not null and end_ts is not null
                     and start_date is null and end_date is null)
    or
    (all_day = true and start_date is not null and end_date is not null
                    and start_ts is null and end_ts is null)
  ),
  unique (caldav_uid, recurrence_id)
);
create index idx_events_timed  on public.events(start_ts)   where deleted_at is null and all_day = false;
create index idx_events_allday on public.events(start_date) where deleted_at is null and all_day = true;

-- ── Inköp ────────────────────────────────────────────────────
create table public.shopping_items (
  id          uuid primary key,          -- klientgenererat (offline-idempotens)
  name        text not null,
  name_norm   text not null default '',
  qty         text,
  checked     boolean not null default false,
  checked_by  text references public.profiles(username),
  checked_at  timestamptz,
  created_by  text not null references public.profiles(username),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  version     int not null default 1,
  archived_at timestamptz,
  deleted_at  timestamptz,
  deleted_by  text references public.profiles(username)
);
create unique index idx_shopping_active_name on public.shopping_items(name_norm)
  where checked = false and archived_at is null and deleted_at is null;
create index idx_shopping_autocomplete on public.shopping_items(name_norm, created_at);

-- ── Att göra ─────────────────────────────────────────────────
create table public.todos (
  id          uuid primary key,
  title       text not null,
  notes       text,
  assignee    text,                      -- username | 'both' | null
  start_date  date,                      -- period ("gör inom start..due")
  due_date    date,
  done        boolean not null default false,
  done_by     text references public.profiles(username),
  done_at     timestamptz,
  created_by  text not null references public.profiles(username),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  version     int not null default 1,
  deleted_at  timestamptz,
  deleted_by  text references public.profiles(username),
  check (start_date is null or (due_date is not null and start_date <= due_date))
);
create index idx_todos_open on public.todos(due_date, created_at)
  where done = false and deleted_at is null;

-- ── Aktivitetslogg + notiser ─────────────────────────────────
create table public.activity_log (
  id          bigint generated always as identity primary key,
  type        text not null,
  actor       text not null references public.profiles(username),
  entity_type text not null,
  entity_id   text not null,
  payload     jsonb,
  created_at  timestamptz not null default now()
);
create index idx_activity_recent on public.activity_log(id desc);

create table public.push_subscriptions (
  id         bigint generated always as identity primary key,
  username   text not null references public.profiles(username),
  endpoint   text not null unique,
  p256dh     text not null,
  auth       text not null,
  created_at timestamptz not null default now(),
  failed_at  timestamptz
);

create table public.notification_prefs (
  username       text primary key references public.profiles(username),
  enabled        boolean not null default true,
  quiet_from     text not null default '21:00',
  quiet_to       text not null default '07:30',
  digest_minutes int not null default 10
);

create table public.notification_queue (
  id          bigint generated always as identity primary key,
  recipient   text not null references public.profiles(username),
  activity_id bigint not null references public.activity_log(id) on delete cascade,
  created_at  timestamptz not null default now(),
  send_after  timestamptz not null,
  sent_at     timestamptz
);
create index idx_queue_unsent on public.notification_queue(recipient, send_after)
  where sent_at is null;

create table public.sync_state (
  username       text primary key references public.profiles(username),
  last_synced_at timestamptz,
  last_error     text,
  failing_since  timestamptz
);

-- ── Triggers: normalisering + version-bump ───────────────────
create or replace function public.tg_shopping_before() returns trigger
language plpgsql as $$
begin
  new.name_norm := lower(trim(new.name));
  if tg_op = 'UPDATE' then
    new.version := old.version + 1;
    new.updated_at := now();
  end if;
  return new;
end $$;
create trigger shopping_before before insert or update on public.shopping_items
  for each row execute function public.tg_shopping_before();

create or replace function public.tg_todos_before() returns trigger
language plpgsql as $$
begin
  if tg_op = 'UPDATE' then
    new.version := old.version + 1;
    new.updated_at := now();
  end if;
  return new;
end $$;
create trigger todos_before before insert or update on public.todos
  for each row execute function public.tg_todos_before();

-- ── Triggers: activity_log (atomärt med mutationen) ──────────
create or replace function public.tg_shopping_activity() returns trigger
language plpgsql security definer set search_path = public as $$
declare actor text := coalesce(my_username(), new.created_by);
begin
  if tg_op = 'INSERT' then
    insert into activity_log(type, actor, entity_type, entity_id, payload)
    values ('shopping.added', actor, 'shopping', new.id::text, jsonb_build_object('name', new.name));
  elsif tg_op = 'UPDATE' then
    if new.archived_at is distinct from old.archived_at then
      return new; -- arkivering loggas som EN rad av rpc:n archive_checked
    elsif new.deleted_at is not null and old.deleted_at is null then
      insert into activity_log(type, actor, entity_type, entity_id, payload)
      values ('shopping.deleted', actor, 'shopping', new.id::text, jsonb_build_object('name', new.name));
    elsif new.deleted_at is null and old.deleted_at is not null then
      insert into activity_log(type, actor, entity_type, entity_id, payload)
      values ('shopping.restored', actor, 'shopping', new.id::text, jsonb_build_object('name', new.name));
    elsif new.checked and not old.checked then
      insert into activity_log(type, actor, entity_type, entity_id, payload)
      values ('shopping.checked', actor, 'shopping', new.id::text, jsonb_build_object('name', new.name));
    elsif not new.checked and old.checked then
      insert into activity_log(type, actor, entity_type, entity_id, payload)
      values ('shopping.unchecked', actor, 'shopping', new.id::text, jsonb_build_object('name', new.name));
    end if;
  end if;
  return new;
end $$;
create trigger shopping_activity after insert or update on public.shopping_items
  for each row execute function public.tg_shopping_activity();

create or replace function public.tg_todos_activity() returns trigger
language plpgsql security definer set search_path = public as $$
declare actor text := coalesce(my_username(), new.created_by);
begin
  if tg_op = 'INSERT' then
    insert into activity_log(type, actor, entity_type, entity_id, payload)
    values ('todo.created', actor, 'todo', new.id::text, jsonb_build_object('title', new.title));
  elsif tg_op = 'UPDATE' then
    if new.deleted_at is not null and old.deleted_at is null then
      insert into activity_log(type, actor, entity_type, entity_id, payload)
      values ('todo.deleted', actor, 'todo', new.id::text, jsonb_build_object('title', new.title));
    elsif new.deleted_at is null and old.deleted_at is not null then
      insert into activity_log(type, actor, entity_type, entity_id, payload)
      values ('todo.restored', actor, 'todo', new.id::text, jsonb_build_object('title', new.title));
    elsif new.done and not old.done then
      insert into activity_log(type, actor, entity_type, entity_id, payload)
      values ('todo.done', actor, 'todo', new.id::text, jsonb_build_object('title', new.title));
    elsif not new.done and old.done then
      insert into activity_log(type, actor, entity_type, entity_id, payload)
      values ('todo.undone', actor, 'todo', new.id::text, jsonb_build_object('title', new.title));
    end if;
  end if;
  return new;
end $$;
create trigger todos_activity after insert or update on public.todos
  for each row execute function public.tg_todos_activity();

-- done_by/checked_at-fält sätts av klienten; säkra upp aktören server-side
create or replace function public.tg_shopping_actor_fields() returns trigger
language plpgsql security definer set search_path = public as $$
declare me text := my_username();
begin
  if me is not null then
    if tg_op = 'UPDATE' and new.checked and not old.checked then
      new.checked_by := me; new.checked_at := now();
    elsif tg_op = 'UPDATE' and not new.checked and old.checked then
      new.checked_by := null; new.checked_at := null;
    end if;
    if tg_op = 'UPDATE' and new.deleted_at is not null and old.deleted_at is null then
      new.deleted_by := me;
    end if;
    if tg_op = 'INSERT' then new.created_by := me; end if;
  end if;
  return new;
end $$;
create trigger shopping_actor before insert or update on public.shopping_items
  for each row execute function public.tg_shopping_actor_fields();

create or replace function public.tg_todos_actor_fields() returns trigger
language plpgsql security definer set search_path = public as $$
declare me text := my_username();
begin
  if me is not null then
    if tg_op = 'UPDATE' and new.done and not old.done then
      new.done_by := me; new.done_at := now();
    elsif tg_op = 'UPDATE' and not new.done and old.done then
      new.done_by := null; new.done_at := null;
    end if;
    if tg_op = 'UPDATE' and new.deleted_at is not null and old.deleted_at is null then
      new.deleted_by := me;
    end if;
    if tg_op = 'INSERT' then new.created_by := me; end if;
  end if;
  return new;
end $$;
create trigger todos_actor before insert or update on public.todos
  for each row execute function public.tg_todos_actor_fields();

-- ── Trigger: notiskö till partnern ───────────────────────────
create or replace function public.tg_activity_queue() returns trigger
language plpgsql security definer set search_path = public as $$
declare partner text; digest int;
begin
  select username into partner from profiles where username <> new.actor limit 1;
  if partner is null then return new; end if;
  select digest_minutes into digest from notification_prefs where username = partner;
  insert into notification_queue (recipient, activity_id, send_after)
  values (partner, new.id, now() + make_interval(mins => coalesce(digest, 10)));
  return new;
end $$;
create trigger activity_queue after insert on public.activity_log
  for each row execute function public.tg_activity_queue();

-- ── RPC:er ───────────────────────────────────────────────────
create or replace function public.archive_checked()
returns table (count bigint, ids uuid[])
language plpgsql security definer set search_path = public as $$
declare v_ids uuid[]; me text := my_username();
begin
  if me is null then raise exception 'not a member'; end if;
  with updated as (
    update shopping_items
    set archived_at = now(), updated_at = now(), version = version + 1
    where checked and archived_at is null and deleted_at is null
    returning id
  )
  select array_agg(id) into v_ids from updated;
  if v_ids is null then
    return query select 0::bigint, '{}'::uuid[];
    return;
  end if;
  insert into activity_log(type, actor, entity_type, entity_id, payload)
  values ('shopping.archived', me, 'shopping', '', jsonb_build_object('count', array_length(v_ids, 1)));
  return query select array_length(v_ids, 1)::bigint, v_ids;
end $$;

create or replace function public.unarchive(p_ids uuid[])
returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0; r uuid;
begin
  if my_username() is null then raise exception 'not a member'; end if;
  foreach r in array p_ids loop
    begin
      update shopping_items
      set archived_at = null, updated_at = now(), version = version + 1
      where id = r and archived_at is not null;
      if found then n := n + 1; end if;
    exception when unique_violation then
      null; -- dubblettskyddet: hoppa över tyst
    end;
  end loop;
  return n;
end $$;

-- ── RLS ──────────────────────────────────────────────────────
alter table public.profiles           enable row level security;
alter table public.caldav_accounts    enable row level security;
alter table public.events             enable row level security;
alter table public.shopping_items     enable row level security;
alter table public.todos              enable row level security;
alter table public.activity_log       enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.notification_prefs enable row level security;
alter table public.notification_queue enable row level security;
alter table public.sync_state         enable row level security;

-- Loginväljaren behöver se de två användarna före inloggning.
create policy profiles_public_read on public.profiles for select using (true);

create policy shopping_member_all on public.shopping_items
  for all using (public.is_member()) with check (public.is_member());
create policy todos_member_all on public.todos
  for all using (public.is_member()) with check (public.is_member());

create policy events_member_read on public.events for select using (public.is_member());
create policy activity_member_read on public.activity_log for select using (public.is_member());
create policy sync_member_read on public.sync_state for select using (public.is_member());

create policy prefs_own on public.notification_prefs
  for all using (username = public.my_username()) with check (username = public.my_username());
create policy push_own on public.push_subscriptions
  for all using (username = public.my_username()) with check (username = public.my_username());
-- caldav_accounts + notification_queue: inga klientpolicies (endast service role).

-- ── Realtime ─────────────────────────────────────────────────
alter publication supabase_realtime add table
  public.shopping_items, public.todos, public.events,
  public.activity_log, public.sync_state;
