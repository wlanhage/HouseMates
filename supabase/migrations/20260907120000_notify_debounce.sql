-- Notiser som glidande fönster (användarbeslut 2026-09-07): varje ny händelse
-- skjuter fram partnerns alla oskickade notisrader, så att EN samlad push går
-- först när det varit tyst i digest_minutes (standard 3 min). Tio avbockningar
-- med en minuts mellanrum blir alltså en notis, inte tio.
create or replace function public.tg_activity_queue() returns trigger
language plpgsql security definer set search_path = public as $$
declare partner text; digest int; due timestamptz;
begin
  select username into partner from profiles where username <> new.actor limit 1;
  if partner is null then return new; end if;
  select digest_minutes into digest from notification_prefs where username = partner;
  due := now() + make_interval(mins => coalesce(digest, 3));
  update notification_queue set send_after = due
    where recipient = partner and sent_at is null;
  insert into notification_queue (recipient, activity_id, send_after)
  values (partner, new.id, due);
  return new;
end $$;

alter table public.notification_prefs alter column digest_minutes set default 3;
update public.notification_prefs set digest_minutes = 3;
