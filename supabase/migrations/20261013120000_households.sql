-- Flera hushåll i samma databas (användarbeslut 2026-10-13). Samma modell som
-- native-appens backend (native/supabase): hushåll för två, inbjudningskod,
-- household_id på all delad data och RLS per hushåll. Befintlig data samlas i
-- ett hushåll för de profiler som finns.

-- ── Hushåll ──────────────────────────────────────────────────
create table public.households (
  id          uuid primary key default gen_random_uuid(),
  invite_code text not null unique,
  created_at  timestamptz not null default now()
);

create table public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id      uuid not null unique references auth.users(id) on delete cascade,
  joined_at    timestamptz not null default now(),
  primary key (household_id, user_id)
);

create table public.join_attempts (
  user_id      uuid not null references auth.users(id) on delete cascade,
  attempted_at timestamptz not null default now()
);
create index join_attempts_by_user on public.join_attempts (user_id, attempted_at);

create or replace function public.my_household_id() returns uuid
language sql stable security definer set search_path = public as $$
  select household_id from household_members where user_id = auth.uid()
$$;

-- Hushållet för en användare (triggers och policyer arbetar med användarnamn).
create or replace function public.household_of(p_username text) returns uuid
language sql stable security definer set search_path = public as $$
  select m.household_id from household_members m join profiles p on p.id = m.user_id
  where p.username = p_username
$$;
revoke execute on function public.household_of(text) from anon;

-- Användarnamnen i ett hushåll. Körs med anroparens rättigheter, så en
-- inloggad användare ser bara sitt eget hushåll.
create or replace function public.household_usernames(p_household uuid) returns text[]
language sql stable set search_path = public as $$
  select coalesce(array_agg(p.username), '{}') from household_members m
  join profiles p on p.id = m.user_id
  where m.household_id = p_household
$$;

-- Sex tecken utan förväxlingsbara (0/O, 1/I).
create or replace function public.new_invite_code() returns text
language plpgsql volatile set search_path = public, extensions as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes bytea := gen_random_bytes(6);
  code text := '';
begin
  for i in 0..5 loop
    code := code || substr(alphabet, 1 + get_byte(bytes, i) % 32, 1);
  end loop;
  return code;
end $$;

create or replace function public.create_household() returns public.households
language plpgsql security definer set search_path = public as $$
declare h households;
begin
  if auth.uid() is null then raise exception 'Du är inte inloggad'; end if;
  if my_household_id() is not null then raise exception 'Du är redan med i ett hushåll'; end if;
  insert into households (invite_code) values (new_invite_code()) returning * into h;
  insert into household_members (household_id, user_id) values (h.id, auth.uid());
  return h;
end $$;

-- Svarar false för en kod som inte finns i stället för att kasta ett fel, så
-- att försöket räknas (ett fel rullar tillbaka insert i join_attempts).
create or replace function public.join_household(p_code text) returns boolean
language plpgsql security definer set search_path = public as $$
declare h households;
begin
  if auth.uid() is null then raise exception 'Du är inte inloggad'; end if;
  if my_household_id() is not null then raise exception 'Du är redan med i ett hushåll'; end if;
  if (select count(*) from join_attempts
      where user_id = auth.uid() and attempted_at > now() - interval '1 hour') >= 10 then
    raise exception 'För många felaktiga koder. Vänta en timme och försök igen.';
  end if;
  -- Låset hindrar att två går med samtidigt och gör hushållet större än två.
  select * into h from households where invite_code = upper(trim(p_code)) for update;
  if h.id is null then
    insert into join_attempts (user_id) values (auth.uid());
    return false;
  end if;
  if (select count(*) from household_members where household_id = h.id) >= 2 then
    raise exception 'Hushållet har redan två medlemmar';
  end if;
  insert into household_members (household_id, user_id) values (h.id, auth.uid());
  update profiles set color = case
    when exists (
      select 1 from household_members m join profiles p on p.id = m.user_id
      where m.household_id = h.id and m.user_id <> auth.uid() and p.color = '#378ADD'
    ) then '#D4537E' else '#378ADD' end
  where id = auth.uid();
  return true;
end $$;

-- ── Befintlig data → ett hushåll ─────────────────────────────
do $$
declare h uuid;
begin
  if exists (select 1 from profiles) then
    insert into households (invite_code) values (new_invite_code()) returning id into h;
    insert into household_members (household_id, user_id) select h, id from profiles;
  end if;
end $$;

do $$
declare t text;
begin
  foreach t in array array['shopping_items', 'todos', 'chores', 'favorites', 'events', 'activity_log', 'caldav_accounts'] loop
    execute format('alter table public.%I add column household_id uuid references public.households(id) on delete cascade', t);
    execute format('update public.%I set household_id = (select id from public.households limit 1)', t);
    execute format('alter table public.%I alter column household_id set default public.my_household_id()', t);
    execute format('alter table public.%I alter column household_id set not null', t);
    execute format('create index %I on public.%I (household_id)', t || '_by_household', t);
  end loop;
end $$;

-- Rader som skapas av service role eller triggers (aktivitet, kalender) får
-- hushållet via användaren när det inte angetts.
create or replace function public.tg_activity_household() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.household_id is null then new.household_id := household_of(new.actor); end if;
  return new;
end $$;
create trigger activity_household before insert on public.activity_log
  for each row execute function public.tg_activity_household();

-- Unikhet per hushåll i stället för i hela databasen.
drop index public.idx_shopping_active_name;
create unique index idx_shopping_active_name on public.shopping_items (household_id, name_norm)
  where checked = false and archived_at is null and deleted_at is null;

alter table public.events drop constraint events_caldav_uid_recurrence_id_key;
alter table public.events add constraint events_household_uid_recurrence_key
  unique (household_id, caldav_uid, recurrence_id);

create unique index caldav_accounts_one_per_household on public.caldav_accounts (household_id);

-- ── Funktioner som tidigare antog en enda användargrupp ─────
create or replace function public.tg_activity_queue() returns trigger
language plpgsql security definer set search_path = public as $$
declare partner text; digest int; due timestamptz;
begin
  select p.username into partner from household_members m join profiles p on p.id = m.user_id
    where m.household_id = new.household_id and p.username <> new.actor limit 1;
  if partner is null then return new; end if;
  select digest_minutes into digest from notification_prefs where username = partner;
  due := now() + make_interval(mins => coalesce(digest, 3));
  update notification_queue set send_after = due
    where recipient = partner and sent_at is null;
  insert into notification_queue (recipient, activity_id, send_after)
  values (partner, new.id, due);
  return new;
end $$;

create or replace function public.archive_checked()
returns table (count bigint, ids uuid[])
language plpgsql security definer set search_path = public as $$
declare v_ids uuid[]; me text := my_username(); hh uuid := my_household_id();
begin
  if hh is null then raise exception 'not a member'; end if;
  with updated as (
    update shopping_items
    set archived_at = now(), updated_at = now(), version = version + 1
    where household_id = hh and checked and archived_at is null and deleted_at is null
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
declare n int := 0; r uuid; hh uuid := my_household_id();
begin
  if hh is null then raise exception 'not a member'; end if;
  foreach r in array p_ids loop
    begin
      update shopping_items
      set archived_at = null, updated_at = now(), version = version + 1
      where id = r and household_id = hh and archived_at is not null;
      if found then n := n + 1; end if;
    exception when unique_violation then
      null;
    end;
  end loop;
  return n;
end $$;

create or replace function public.suggest_shopping(q text default '')
returns table (name text)
language sql stable security definer set search_path = public as $$
  select s.name
  from shopping_items s
  where s.household_id = public.my_household_id()
    and (q = '' or s.name_norm like lower(trim(q)) || '%')
  group by s.name_norm, s.name
  order by count(*) desc, max(s.created_at) desc
  limit 8
$$;

create or replace function public.caldav_linked_by() returns text
language sql security definer set search_path = public stable as $$
  select username from caldav_accounts
  where household_id = public.my_household_id()
  order by updated_at limit 1
$$;

create or replace function public.caldav_unlink() returns void
language plpgsql security definer set search_path = public as $$
declare me text := my_username(); hh uuid := my_household_id();
begin
  if hh is null then raise exception 'not a member'; end if;
  delete from caldav_accounts where username = me;
  update sync_state set last_synced_at = null, last_error = null, failing_since = null
    where username = me;
  if not exists (select 1 from caldav_accounts where household_id = hh) then
    delete from events where household_id = hh;
  end if;
end $$;

-- ── RLS per hushåll ──────────────────────────────────────────
drop policy profiles_member_read on public.profiles;
drop policy shopping_member_all on public.shopping_items;
drop policy todos_member_all on public.todos;
drop policy chores_member_all on public.chores;
drop policy favorites_member_all on public.favorites;
drop policy events_member_read on public.events;
drop policy activity_member_read on public.activity_log;
drop policy sync_member_read on public.sync_state;

alter table public.households        enable row level security;
alter table public.household_members enable row level security;
alter table public.join_attempts     enable row level security; -- inga policyer: bara join_household

create policy households_own on public.households
  for select using (id = public.my_household_id());
create policy household_members_own on public.household_members
  for select using (household_id = public.my_household_id());

create policy profiles_household_read on public.profiles for select using (
  id = auth.uid()
  or exists (select 1 from household_members m
             where m.user_id = profiles.id and m.household_id = public.my_household_id())
);
create policy shopping_household on public.shopping_items
  for all using (household_id = public.my_household_id()) with check (household_id = public.my_household_id());
create policy todos_household on public.todos
  for all using (household_id = public.my_household_id()) with check (household_id = public.my_household_id());
create policy chores_household on public.chores
  for all using (household_id = public.my_household_id()) with check (household_id = public.my_household_id());
create policy favorites_household on public.favorites
  for all using (household_id = public.my_household_id()) with check (household_id = public.my_household_id());
create policy events_household_read on public.events
  for select using (household_id = public.my_household_id());
create policy activity_household_read on public.activity_log
  for select using (household_id = public.my_household_id());
create policy sync_household_read on public.sync_state
  for select using (public.household_of(username) = public.my_household_id());

alter publication supabase_realtime add table public.household_members;
