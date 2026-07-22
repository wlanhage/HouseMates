-- Seed för LOKAL utveckling (supabase db reset). Skapa aldrig prod-användare
-- så här – i prod skapas de via dashboarden (Authentication → Add user).
-- Login lokalt: anna@housemates.local / devlosen (och erik@...).

-- Två auth-användare (GoTrue-kompatibelt: bcrypt via pgcrypto)
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  email_change_token_current, phone_change, phone_change_token, reauthentication_token
)
values
  ('00000000-0000-0000-0000-000000000000', '11111111-1111-1111-1111-111111111111',
   'authenticated', 'authenticated', 'anna@housemates.local',
   crypt('devlosen', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now(),
   '', '', '', '', '', '', '', ''),
  ('00000000-0000-0000-0000-000000000000', '22222222-2222-2222-2222-222222222222',
   'authenticated', 'authenticated', 'erik@housemates.local',
   crypt('devlosen', gen_salt('bf')), now(),
   '{"provider":"email","providers":["email"]}', '{}', now(), now(),
   '', '', '', '', '', '', '', '');

insert into auth.identities (
  id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at
)
values
  (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111',
   '{"sub":"11111111-1111-1111-1111-111111111111","email":"anna@housemates.local"}', 'email', now(), now(), now()),
  (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', '22222222-2222-2222-2222-222222222222',
   '{"sub":"22222222-2222-2222-2222-222222222222","email":"erik@housemates.local"}', 'email', now(), now(), now());

insert into public.profiles (id, username, name, color, email) values
  ('11111111-1111-1111-1111-111111111111', 'anna', 'Anna (test)', '#D4537E', 'anna@housemates.local'),
  ('22222222-2222-2222-2222-222222222222', 'erik', 'Erik (test)', '#378ADD', 'erik@housemates.local');

insert into public.notification_prefs (username) values ('anna'), ('erik');
insert into public.sync_state (username) values ('anna'), ('erik');

-- Lite testdata så vyerna inte är tomma
insert into public.shopping_items (id, name, created_by) values
  (gen_random_uuid(), 'Mjölk',  'anna'),
  (gen_random_uuid(), 'Bröd',   'erik'),
  (gen_random_uuid(), 'Kaffe',  'anna');

insert into public.todos (id, title, assignee, due_date, created_by) values
  (gen_random_uuid(), 'Boka bilbesiktning', 'erik', current_date + 7, 'anna'),
  (gen_random_uuid(), 'Planera helgen',     'both', null,             'erik');
