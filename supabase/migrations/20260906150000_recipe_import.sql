-- Receptimport (användarbeslut 2026-09-06): favoriter kan komma från en
-- receptsida (bild + källa) och sparas via en iPhone-genväg med personlig nyckel.

alter table public.favorites
  add column image_url  text,
  add column source_url text;

-- Nyckel som genvägen skickar i headern x-import-token. En per användare,
-- skapas/byts i Inställningar. Endast ägaren kan läsa sin nyckel.
create table public.import_tokens (
  username   text primary key references public.profiles(username),
  token      text not null unique,
  created_at timestamptz not null default now()
);
alter table public.import_tokens enable row level security;
create policy import_tokens_own on public.import_tokens
  for all using (username = public.my_username()) with check (username = public.my_username());
