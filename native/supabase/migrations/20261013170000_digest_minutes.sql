-- Hur länge det ska ha varit tyst innan notisen skickas, per mottagare, som webbappens
-- digest_minutes ("Skicka när det varit tyst i (minuter)", 0–120, standard 3). Den som inte
-- sparat några inställningar får standardvärdet.
alter table public.notification_prefs
  add column digest_minutes int not null default 3 check (digest_minutes between 0 and 120);

create or replace function public.tg_activity_queue() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  due timestamptz;
  member_id uuid;
begin
  for member_id in
    select user_id from household_members where household_id = new.household_id and user_id <> new.actor
  loop
    due := now() + make_interval(mins => coalesce(
      (select digest_minutes from notification_prefs where user_id = member_id), 3));
    update notification_queue set send_after = due where recipient = member_id and sent_at is null;
    insert into notification_queue (recipient, activity_id, send_after) values (member_id, new.id, due);
  end loop;
  return new;
end $$;

drop function public.notify_delay();
