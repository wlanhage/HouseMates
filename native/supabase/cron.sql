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
  delete from public.notification_queue where sent_at < now() - interval '7 days';
  delete from public.activity_log where created_at < now() - interval '90 days';
  $$
);
