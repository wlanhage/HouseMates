# Parplaneraren

Planerings-PWA för två personer: delad iCloud-kalender (CalDAV), inköpslista
och att göra-lista, med hemskärm och aktivitetsflöde.

Den här mappen är en **startpunkt för AI-driven implementation**:

| Fil | Roll |
|---|---|
| `IMPLEMENTATION_SPEC.md` | Hela specen – normativ, ändras ej |
| `CLAUDE.md` | Instruktioner som Claude Code läser automatiskt |
| `db/schema.sql`, `db/seed.dev.sql` | Databasen – normativa, ändras ej |
| `db/migrate.ts` | Skapar dev-databasen |
| `DECISIONS.md` | Logg för val där specen är tyst |
| Övrigt (package.json, configfiler, src/) | Verifierat SvelteKit-skelett att bygga vidare på |

## Kom igång (en gång)

Krav: Node 20+.

```bash
npm install
cp .env.example .env
```

Fyll i `.env`:

```bash
# Krypteringsnyckel (APP_ENCRYPTION_KEY):
node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"

# VAPID-nycklar för push (VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY):
npx web-push generate-vapid-keys
```

Skapa databasen och starta:

```bash
npm run db:setup     # dev.db med testanvändarna anna/erik (lösenord: devlosen)
npm run dev
```

## Starta bygget med Claude Code

Öppna Claude Code i den här mappen och ge den:

> Läs CLAUDE.md och IMPLEMENTATION_SPEC.md i sin helhet. Implementera sedan
> milstolpe M1 enligt spec §16. Stanna när M1:s acceptanskriterier är
> uppfyllda och rapportera innan du fortsätter med M2.

Kör en milstolpe i taget (M1 → M6) och testa acceptanskriterierna mellan varje –
det ger mycket bättre resultat än att be om allt på en gång.
(Claude Code: se https://docs.claude.com/en/docs/claude-code/overview)

## Viktigt under utveckling

- **Testkalender:** dev pekar mot `CALDAV_CALENDAR_NAME=Gemensamt-test`.
  Skapa en kalender med det namnet i iCloud och dela mellan er – kör aldrig
  utveckling mot er riktiga "Gemensamt".
- App-specifika lösenord skapas på https://account.apple.com →
  Logga in och säkerhet → App-specifika lösenord (behövs först i milstolpe M4).
- **iOS-push:** notiser fungerar bara när appen är installerad på hemskärmen
  (Dela → Lägg till på hemskärmen), inte i Safari-flik.
- Nollställa databasen: `npm run db:reset`.

## Kommandon

```bash
npm run dev        # dev-server
npm run build      # produktionsbygge (adapter-node)
npm run preview    # kör bygget lokalt
npm test           # vitest
npm run check      # typkontroll/svelte-check
npm run db:setup   # skapa dev.db (schema + seed)
npm run db:reset   # radera + återskapa dev.db
```

## Drift (när det är dags)

Långlivad Node-process krävs (bakgrundsjobb för synk/notiser) – liten VPS
eller Fly.io/Railway, inte serverless. HTTPS är obligatoriskt (cookies, push,
CalDAV-lösenord). Backup = kopiera SQLite-filen nattligen (t.ex. litestream
eller `sqlite3 .backup` + rsync).
