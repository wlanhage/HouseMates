# Deploy: Supabase (gratis, inget kort) + GitHub Pages

Arkitektur: statisk PWA (GitHub Pages) + Supabase Free (Postgres, Auth,
Realtime, Edge Functions, pg_cron). Ingen egen server.

**Använd ett PRIVAT Supabase-konto** (logga in med GitHub `wlanhage`).

## Din del (~5 min)

1. Skapa konto på <https://supabase.com> (GitHub-inloggning, inget kort).
2. Skapa ett projekt (region t.ex. `eu-north-1` Stockholm). Spara
   databas-lösenordet.
3. Skapa en **access token**: <https://supabase.com/dashboard/account/tokens>
   och ge den till Claude (eller kör stegen nedan själv).

## Deploy-steg (Claude kör dessa via CLI med din token)

```bash
export SUPABASE_ACCESS_TOKEN=<token>
supabase link --project-ref <ref>          # <ref> från projektets URL
supabase db push                           # migrationer (schema/RLS/triggers)
supabase functions deploy caldav-sync caldav-setup caldav-select event-write notify

# Hemligheter
node deploy/gen-vapid.mjs                  # ger raderna nedan
supabase secrets set \
  CALDAV_ENC_KEY=$(openssl rand -base64 32) \
  CALDAV_SERVER=https://caldav.icloud.com \
  CALDAV_CALENDAR_NAME=Gemensamt \
  TZ_DEFAULT=Europe/Stockholm \
  VAPID_SUBJECT=mailto:er@mejl.se \
  VAPID_KEYS_JSON='<från gen-vapid>'
```

**Användare** (Dashboard → Authentication → Add user, "Auto confirm"):
skapa två användare med e-post + lösenord, t.ex. `william@housemates.local`.
Koppla profiler i SQL Editor:

```sql
insert into public.profiles (id, username, name, color, email)
select id, 'william', 'William', '#D4537E', email from auth.users where email = 'william@housemates.local';
-- upprepa för partnern med '#378ADD'
insert into public.notification_prefs (username) values ('william'), ('<partner>');
insert into public.sync_state (username) values ('william'), ('<partner>');
```

**Cron:** öppna `supabase/cron.sql`, ersätt `__PROJECT_URL__` +
`__SERVICE_KEY__` (Settings → API → service_role) och kör i SQL Editor.

**Frontend (GitHub Pages):** bygg med projektets värden i `.env`:

```
PUBLIC_SUPABASE_URL=https://<ref>.supabase.co
PUBLIC_SUPABASE_ANON_KEY=<anon/publishable key>
PUBLIC_VAPID_KEY=<från gen-vapid>
PUBLIC_APP_NAME=Planeraren
```

`npm run build` → innehållet i `build/` publiceras (repo `wlanhage.github.io`
eller Pages-workflow i detta repo).

## Gratisnivåns villkor

- Projektet pausas efter ~1 veckas total inaktivitet – cron-anropen håller
  det normalt vaket; annars återställs det med ett klick i dashboarden.
- Backup: Free har ingen automatisk PITR – ta en manuell export då och då
  (Dashboard → Database → Backups, eller `supabase db dump`).
