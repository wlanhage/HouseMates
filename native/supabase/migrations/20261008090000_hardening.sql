-- Rättelser efter en granskning av hela backend.

-- ── Aktörsfält ───────────────────────────────────────────────
-- Vem som skapat eller gjort något sätts bara av servern. null släpps ändå igenom: när ett konto
-- raderas sätter databasen fälten till null (on delete set null), och den ändringen går genom
-- samma trigger. Att låsa även null fick tidigare radera konto att misslyckas.

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
  new.created_by := case when new.created_by is null then null else old.created_by end;
  if new.done and not old.done then
    new.done_by := coalesce(auth.uid(), new.done_by);
    new.done_at := now();
  elsif not new.done and old.done then
    new.done_by := null;
    new.done_at := null;
  else
    new.done_by := case when new.done_by is null then null else old.done_by end;
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
  new.created_by := case when new.created_by is null then null else old.created_by end;
  if new.last_done_at > coalesce(old.last_done_at, '-infinity'::timestamptz) then
    new.last_done_at := least(new.last_done_at, now());
    new.last_done_by := coalesce(auth.uid(), new.last_done_by);
  elsif new.last_done_at is null then
    new.last_done_by := null;
  elsif new.last_done_at is distinct from old.last_done_at then
    new.last_done_by := coalesce(old.last_done_by, auth.uid(), new.last_done_by);
  elsif new.last_done_by is not null then
    new.last_done_by := old.last_done_by;
  end if;
  return new;
end $$;

create or replace function public.tg_shopping_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.name := trim(new.name);
  new.name_norm := lower(new.name);
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
    new.checked_by := case when new.checked then new.created_by end;
    new.checked_at := case when new.checked then now() end;
    return new;
  end if;
  new.created_by := case when new.created_by is null then null else old.created_by end;
  if new.checked and not old.checked then
    new.checked_by := auth.uid();
    new.checked_at := now();
  elsif not new.checked and old.checked then
    new.checked_by := null;
    new.checked_at := null;
  else
    new.checked_by := case when new.checked_by is null then null else old.checked_by end;
    new.checked_at := old.checked_at;
  end if;
  return new;
end $$;

create or replace function public.tg_favorites_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.name := trim(new.name);
  if tg_op = 'INSERT' then
    new.created_by := coalesce(auth.uid(), new.created_by);
  else
    new.created_by := case when new.created_by is null then null else old.created_by end;
  end if;
  return new;
end $$;

-- ── Nytt konto ───────────────────────────────────────────────
-- Ett namn över 40 tecken fick registreringen att misslyckas med ett engelskt serverfel.
create or replace function public.tg_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, name)
  values (new.id, left(coalesce(nullif(trim(new.raw_user_meta_data->>'name'), ''), split_part(new.email, '@', 1)), 40));
  return new;
end $$;

-- ── Inbjudningskoder ─────────────────────────────────────────
-- Åtta tecken (drygt en biljon koder) och högst tio felaktiga koder i timmen per person, så att
-- ingen kan gissa sig in i någon annans hushåll.
create or replace function public.new_invite_code() returns text
language plpgsql volatile set search_path = public, extensions as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  bytes bytea := gen_random_bytes(8);
  code text := '';
begin
  for i in 0..7 loop
    code := code || substr(alphabet, 1 + get_byte(bytes, i) % 32, 1);
  end loop;
  return code;
end $$;

update public.households set invite_code = public.new_invite_code();

create table public.join_attempts (
  user_id      uuid not null references auth.users(id) on delete cascade,
  attempted_at timestamptz not null default now()
);
create index join_attempts_by_user on public.join_attempts (user_id, attempted_at);
alter table public.join_attempts enable row level security;   -- inga policyer: bara join_household når tabellen

-- Svarar false för en kod som inte finns, i stället för att kasta ett fel: ett fel skulle rulla
-- tillbaka försöket, så att det inte räknades.
drop function public.join_household(text);
create function public.join_household(p_code text) returns boolean
language plpgsql security definer set search_path = public as $$
declare h households;
begin
  if auth.uid() is null then raise exception 'Du är inte inloggad'; end if;
  if my_household_id() is not null then raise exception 'Du är redan med i ett hushåll'; end if;
  if (select count(*) from join_attempts
      where user_id = auth.uid() and attempted_at > now() - interval '1 hour') >= 10 then
    raise exception 'För många felaktiga koder. Vänta en timme och försök igen.';
  end if;
  -- Låset hindrar att två personer går med samtidigt och gör hushållet större än två.
  select * into h from households where invite_code = upper(trim(p_code)) for update;
  if h.id is null then
    insert into join_attempts (user_id) values (auth.uid());
    return false;
  end if;
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
  return true;
end $$;

-- ── Push-adresser ────────────────────────────────────────────
-- Tokenen hamnar i en adress till Apple, så bara hexadecimala tokens godtas, och fem telefoner
-- per person räcker.
create or replace function public.register_device(p_token text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Du är inte inloggad'; end if;
  if p_token !~ '^[0-9a-f]{64,200}$' then raise exception 'Ogiltig notisadress'; end if;
  insert into device_tokens (token, user_id) values (p_token, auth.uid())
  on conflict (token) do update set user_id = auth.uid(), updated_at = now();
  delete from device_tokens where user_id = auth.uid() and token in (
    select token from device_tokens where user_id = auth.uid() order by updated_at desc offset 5
  );
end $$;

-- ── Index för främmande nycklar ──────────────────────────────
-- Raderingar (konto, nattlig städning) och notis-workern letar på de här kolumnerna.
create index notification_queue_by_activity on public.notification_queue (activity_id);
create index notification_queue_by_recipient on public.notification_queue (recipient);
create index activity_by_actor on public.activity_log (actor);
create index device_tokens_by_user on public.device_tokens (user_id);

alter function public.notify_delay() set search_path = public;

-- ── Behörigheter ─────────────────────────────────────────────
-- Inget i appen läses eller skrivs utan inloggning. RLS skyddar redan; det här tar bort
-- standardbehörigheterna för den anonyma rollen helt.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on sequences from anon;
alter default privileges in schema public revoke execute on functions from public, anon;
