-- ============================================================
-- Schemaläggning för native-projektet (körs EN gång i SQL Editor
-- på det hostade projektet – ersätt platshållarna först):
--   __PROJECT_URL__  = https://<ref>.supabase.co
--   __CRON_SECRET__  = samma värde som secret:en CRON_SECRET
-- Kräver pg_cron + pg_net (aktiva som standard i Supabase).
-- ============================================================

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Notis-worker varje minut
select cron.schedule(
  'notify', '* * * * *',
  $$
  select net.http_post(
    url := '__PROJECT_URL__/functions/v1/notify',
    headers := jsonb_build_object('x-cron-secret', '__CRON_SECRET__', 'Content-Type', 'application/json'),
    body := '{}'::jsonb
  );
  $$
);

-- Städning dagligen 04:00
select cron.schedule(
  'cleanup', '0 4 * * *',
  $$
  delete from public.shopping_items where deleted_at < now() - interval '30 days';
  delete from public.todos where deleted_at < now() - interval '30 days';
  delete from public.todos where done and done_at < now() - interval '30 days';
  delete from public.chores where deleted_at < now() - interval '30 days';
  delete from public.favorites where deleted_at < now() - interval '30 days';
  delete from public.event_assignees where deleted_at < now() - interval '30 days';
  delete from public.join_attempts where attempted_at < now() - interval '1 day';
  -- Telefoner som inte öppnat appen på 90 dagar (appen förnyar adressen vid varje start).
  delete from public.device_tokens where updated_at < now() - interval '90 days';
  -- Hushåll utan medlemmar, t.ex. om ett konto raderats direkt i Supabase.
  delete from public.households h where not exists (select 1 from public.household_members m where m.household_id = h.id);
  -- pg_cron loggar varje körning av notify (en per minut).
  delete from cron.job_run_details where end_time < now() - interval '7 days';
  delete from public.notification_queue where sent_at < now() - interval '7 days';
  delete from public.activity_log where created_at < now() - interval '90 days';
  $$
);
