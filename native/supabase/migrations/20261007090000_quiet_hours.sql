-- Tysta timmar: notiser som skulle skickas under den egna natten väntar tills den tar slut.
-- Tidszonen sparas från telefonen, så att det stämmer även för användare utanför Sverige.
create table public.notification_prefs (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  quiet_enabled boolean not null default false,
  quiet_from    text not null default '22:00' check (quiet_from ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  quiet_to      text not null default '07:00' check (quiet_to ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  time_zone     text not null default 'Europe/Stockholm' check (char_length(time_zone) between 1 and 64),
  updated_at    timestamptz not null default now()
);

alter table public.notification_prefs enable row level security;
create policy prefs_own on public.notification_prefs for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
