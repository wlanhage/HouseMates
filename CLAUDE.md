# CLAUDE.md – Parplaneraren

Du bygger en planerings-PWA för två personer (ett par): delad iCloud-kalender
via CalDAV, inköpslista och att göra-lista. **`IMPLEMENTATION_SPEC.md` är hela
sanningen – läs den i sin helhet innan du skriver någon kod.**

## Arbetssätt

- Bygg **milstolpe för milstolpe** enligt spec §16, i ordning M1 → M6.
  Efter varje milstolpe: kör verifieringen nedan, gå igenom milstolpens
  acceptanskriterier punkt för punkt, och rapportera status till användaren
  innan du påbörjar nästa.
- **Normativa filer som inte får ändras:** `IMPLEMENTATION_SPEC.md`,
  `db/schema.sql`, `db/seed.dev.sql`. Behöver schemat ändras för att lösa
  ett verkligt problem: föreslå ändringen för användaren först och invänta ok.
- Där specen är tyst: välj det **enklaste** som uppfyller acceptanskriterierna
  och logga valet i `DECISIONS.md` (datum, val, en rads motivering).
- Bygg **ingenting** ur spec §17 (icke-mål) – även om det verkar litet.
- Projektskelettet (package.json, configfiler, migrate.ts, placeholder-routes)
  finns redan och är verifierat – bygg vidare på det, skriv inte om det från
  scratch.

## Kommandon

- `npm run dev` – dev-server
- `npm run db:setup` – skapa dev.db från schema + seed (körs en gång)
- `npm run db:reset` – radera och återskapa dev.db
- `npm test` – vitest
- `npm run check` – svelte-check/typkontroll
- `npm run build && npm run preview` – produktionsbygge

## Teknik och stil

- Stacken i spec §2 är **bindande**. Inga nya beroenden utan att logga i
  `DECISIONS.md` med motivering.
- TypeScript strikt läge. Svelte 5 (runes). Ingen ORM – prepared statements
  via better-sqlite3, och **mutation + activity_log-rad i samma transaktion**.
- All användarvänd text på **svenska**.
- Hemligheter läses via `$env/dynamic/private`. Logga aldrig CalDAV-credentials
  eller sessions-tokens; sanera CalDAV-felmeddelanden innan de sparas.
- Klientgenererade UUID v4 som id för shopping/todos/events (offline-idempotens).

## Verifiering per milstolpe

Innan en milstolpe rapporteras klar: `npm run check` och `npm test` gröna,
plus manuell koll av milstolpens acceptanskriterier i spec §16.

M4–M5 kräver riktiga iCloud-uppgifter och en iPhone – det kan du inte testa
själv. Be användaren testa mot **testkalendern** (`CALDAV_CALENDAR_NAME` i
`.env`, "Gemensamt-test") och invänta bekräftelse. Kör **aldrig** mot deras
riktiga kalender under utveckling.

## Vanliga fällor (från planeringen – gör inte dessa fel)

- Heldagsevent är rena datum (`start_date`/`end_date`, end exklusivt) –
  konvertera dem aldrig till midnatt-UTC.
- Vid CalDAV-uppdatering: utgå från `raw_ics` och mutera bara ändrade fält,
  så att larm/deltagare m.m. bevaras. Skicka alltid `If-Match: <etag>`.
- HTTP 412 från iCloud är ett normalflöde (någon hann före) – resynka
  resursen och svara `409 caldav_conflict`, skriv aldrig över tyst.
- Dubblettkonflikt på inköp (partiellt unikt index) är också normalflöde –
  svara 200 med befintlig vara + `merged: true`.
- Externa raderingar (upptäckta via synk) hårdraderas ur cachen; endast
  app-raderingar är soft delete med ångra.
