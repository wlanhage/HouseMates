-- HouseMates native: hushåll för par, inköpslista, aktivitetslogg och notiskö.
-- Mönstren kommer från webbappens schema (supabase/migrations i repo-roten),
-- men allt är knutet till ett hushåll så att många par kan dela databasen.
-- Kalendern ligger i telefonernas iCloud-kalender (EventKit); här sparas bara
-- vilken kalender hushållet delar och vad som hänt i den (för notiser).

-- ── Profiler ─────────────────────────────────────────────────
create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  name       text not null check (char_length(trim(name)) between 1 and 40),
  created_at timestamptz not null default now()
);

create or replace function public.tg_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, name)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data->>'name'), ''), split_part(new.email, '@', 1)));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.tg_new_user();

-- ── Hushåll ──────────────────────────────────────────────────
create table public.households (
  id                  uuid primary key default gen_random_uuid(),
  invite_code         text not null unique,
  calendar_title      text,
  calendar_event_uids text[] not null default '{}',
  created_at          timestamptz not null default now()
);

create table public.household_members (
  household_id uuid not null references public.households(id) on delete cascade,
  user_id      uuid not null unique references auth.users(id) on delete cascade,
  joined_at    timestamptz not null default now(),
  primary key (household_id, user_id)
);

create or replace function public.my_household_id() returns uuid
language sql stable security definer set search_path = public as $$
  select household_id from household_members where user_id = auth.uid()
$$;

-- Sex tecken utan förväxlingsbara (0/O, 1/I). gen_random_bytes: koden går inte att förutsäga.
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
  return h;
end $$;

-- Vilken kalender hushållet delar: titel + UID för några händelser i den,
-- så att partnerns telefon hittar samma kalender (native/README.md, väg A).
create or replace function public.set_calendar_link(p_title text, p_uids text[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  if my_household_id() is null then raise exception 'Du är inte med i något hushåll'; end if;
  if cardinality(p_uids) > 10 then raise exception 'För många händelser i kopplingen'; end if;
  update households set calendar_title = left(p_title, 100), calendar_event_uids = p_uids
  where id = my_household_id();
end $$;

-- ── Inköpslista ──────────────────────────────────────────────
create table public.shopping_items (
  id           uuid primary key,             -- klientgenererat (offline-idempotens)
  household_id uuid not null default public.my_household_id()
               references public.households(id) on delete cascade,
  name         text not null check (char_length(trim(name)) between 1 and 80),
  name_norm    text not null default '',
  checked      boolean not null default false,
  checked_by   uuid references auth.users(id) on delete set null,
  checked_at   timestamptz,
  created_by   uuid references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  deleted_at   timestamptz                   -- mjuk radering: ger ändringshändelser som går att filtrera
);
create unique index shopping_open_name on public.shopping_items (household_id, name_norm)
  where not checked and deleted_at is null;
create index shopping_by_household on public.shopping_items (household_id, created_at)
  where deleted_at is null;

-- Aktörsfält sätts på servern, oavsett vad klienten skickar.
create or replace function public.tg_shopping_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.name := trim(new.name);
  new.name_norm := lower(new.name);
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
    new.checked_by := case when new.checked then new.created_by end;
    new.checked_at := case when new.checked then now() end;
  elsif new.checked and not old.checked then
    new.checked_by := auth.uid();
    new.checked_at := now();
  elsif not new.checked and old.checked then
    new.checked_by := null;
    new.checked_at := null;
  end if;
  return new;
end $$;
create trigger shopping_before before insert or update on public.shopping_items
  for each row execute function public.tg_shopping_before();

-- ── Aktivitetslogg och notiskö ───────────────────────────────
create table public.activity_log (
  id           bigint generated always as identity primary key,
  household_id uuid not null references public.households(id) on delete cascade,
  actor        uuid not null references auth.users(id) on delete cascade,
  type         text not null,                -- 'shopping.added', 'event.created' … (läses av digest.ts)
  entity_id    text not null,
  payload      jsonb,
  created_at   timestamptz not null default now()
);
create index activity_by_household on public.activity_log (household_id, id desc);

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
create trigger shopping_activity after insert or update on public.shopping_items
  for each row execute function public.tg_shopping_activity();

-- Kalenderhändelser finns bara i telefonerna; appen rapporterar vad den gjort.
create or replace function public.log_calendar_activity(p_type text, p_event_uid text, p_title text, p_start text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_type not in ('event.created', 'event.updated', 'event.deleted') then
    raise exception 'Okänd kalenderhändelse: %', p_type;
  end if;
  if my_household_id() is null then raise exception 'Du är inte med i något hushåll'; end if;
  insert into activity_log (household_id, actor, type, entity_id, payload)
  values (my_household_id(), auth.uid(), p_type, left(p_event_uid, 200),
          jsonb_build_object('title', left(p_title, 200), 'start', left(p_start, 40)));
end $$;

create table public.notification_queue (
  id          bigint generated always as identity primary key,
  recipient   uuid not null references auth.users(id) on delete cascade,
  activity_id bigint not null references public.activity_log(id) on delete cascade,
  send_after  timestamptz not null,
  sent_at     timestamptz
);
create index notification_due on public.notification_queue (send_after) where sent_at is null;

create or replace function public.notify_delay() returns interval
language sql immutable as $$ select interval '3 minutes' $$;

-- Glidande fönster (webbappens beslut 2026-09-07): varje ny händelse skjuter fram
-- mottagarens oskickade rader, så att EN samlad notis går när det varit tyst en stund.
create or replace function public.tg_activity_queue() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  due timestamptz := now() + notify_delay();
  member_id uuid;
begin
  for member_id in
    select user_id from household_members where household_id = new.household_id and user_id <> new.actor
  loop
    update notification_queue set send_after = due where recipient = member_id and sent_at is null;
    insert into notification_queue (recipient, activity_id, send_after) values (member_id, new.id, due);
  end loop;
  return new;
end $$;
create trigger activity_queue after insert on public.activity_log
  for each row execute function public.tg_activity_queue();

-- ── Push-enheter ─────────────────────────────────────────────
create table public.device_tokens (
  token      text primary key,               -- APNs-token (hex)
  user_id    uuid not null references auth.users(id) on delete cascade,
  updated_at timestamptz not null default now()
);

-- En telefon kan byta konto; tokenen följer den som är inloggad nu.
create or replace function public.register_device(p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Du är inte inloggad'; end if;
  insert into device_tokens (token, user_id) values (p_token, auth.uid())
  on conflict (token) do update set user_id = auth.uid(), updated_at = now();
end $$;

create or replace function public.unregister_device(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from device_tokens where token = p_token and user_id = auth.uid()
$$;

-- ── Behörigheter (RLS) ───────────────────────────────────────
alter table public.profiles enable row level security;
alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.shopping_items enable row level security;
alter table public.activity_log enable row level security;
alter table public.notification_queue enable row level security;
alter table public.device_tokens enable row level security;

create policy profiles_read on public.profiles for select using (
  id = auth.uid()
  or id in (select user_id from public.household_members where household_id = public.my_household_id())
);
create policy profiles_update_own on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

create policy households_read on public.households for select using (id = public.my_household_id());
create policy members_read on public.household_members for select using (household_id = public.my_household_id());

create policy shopping_member on public.shopping_items for all
  using (household_id = public.my_household_id())
  with check (household_id = public.my_household_id());

create policy activity_read on public.activity_log for select using (household_id = public.my_household_id());
-- notification_queue och device_tokens: inga policyer, bara servern och RPC:erna når dem.

alter publication supabase_realtime add table public.shopping_items;
