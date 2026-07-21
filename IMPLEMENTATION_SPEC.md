# Parplaneraren – komplett implementationsspec v1

> **Till dig som implementerar (AI eller människa):** Detta dokument är hela sanningen.
> Följ det strikt. Där dokumentet är tyst: välj det enklaste som uppfyller acceptans-
> kriterierna i §16, och dokumentera valet i en `DECISIONS.md`. Fråga inte användaren
> om saker som redan är specificerade här. Filerna `schema.sql` och `seed.dev.sql`
> levereras tillsammans med specen och läggs i `db/` – skriv inte om dem, bygg mot dem.

## 1. Syfte och översikt

En planerings-PWA för två personer (ett par). Tre moduler: **delad kalender**
(synkad tvåvägs mot en delad iCloud-kalender via CalDAV), **inköpslista** och
**att göra-lista** (båda helt i egen databas). En **hemskärm** visar dagens
händelser och ett aktivitetsflöde ("Anna bockade av 4 varor").

Grundprincip: **iCloud är master för kalendern** (appen håller en cache),
**appens databas är master för inköp/todos**. Privata kalendrar berörs aldrig –
appen känner bara till exakt en kalender per person: den delade ("Gemensamt").

Användarna: exakt 2, skapas via seed – ingen öppen registrering.

## 2. Teknikstack (bindande beslut)

| Del | Val | Motivering |
|---|---|---|
| Ramverk | SvelteKit 2 + TypeScript | Fullstack i ett projekt, litet, bra PWA-stöd |
| Runtime | Node 20+, långlivad serverprocess (`adapter-node`) | Bakgrundsjobb kräver process som lever – INTE serverless |
| Databas | SQLite via `better-sqlite3` | Två användare, backup = filkopia |
| CalDAV | `tsdav` | Discovery, sync-report, PUT/DELETE |
| iCal-parsning | `ical.js` (ICAL) | Parsning + RRULE-expansion |
| Lösenordshash | `argon2` | |
| Kryptering av CalDAV-lösenord | Node `crypto`, AES-256-GCM | Nyckel via env |
| Web push | `web-push` (VAPID) | |
| Scheduling | `node-cron` i serverprocessen | |
| PWA | `vite-plugin-pwa` (Workbox) | Precache av appskal |
| Klientlagring | IndexedDB via `idb` | Spegel + mutationskö |
| Test | `vitest` | |

Inga andra tunga beroenden (ingen ORM, inget kalenderbibliotek i frontend,
inget state-management-bibliotek – Sveltes stores räcker).

## 3. Repostruktur

```
par-planeraren/
├── db/
│   ├── schema.sql            # levereras – kör vid setup
│   ├── seed.dev.sql          # levereras – endast dev
│   └── migrate.ts            # kör schema om DB saknas; enkel migrationsrunner
├── src/
│   ├── lib/
│   │   ├── server/
│   │   │   ├── db.ts         # better-sqlite3-instans, prepared statements
│   │   │   ├── auth.ts       # sessioner, cookies, login
│   │   │   ├── crypto.ts     # AES-256-GCM encrypt/decrypt
│   │   │   ├── activity.ts   # logActivity() – anropas av ALLA mutationer
│   │   │   ├── notify.ts     # kö-inläggning + digest-worker
│   │   │   ├── sse.ts        # klientregister + broadcast()
│   │   │   ├── caldav/
│   │   │   │   ├── client.ts     # tsdav-uppkoppling, discovery
│   │   │   │   ├── sync.ts       # pollloop, sync-token, upsert till cache
│   │   │   │   ├── ics.ts        # parse/serialize, RRULE-expansion, mappning
│   │   │   │   └── write.ts      # create/update/delete med etag-hantering
│   │   │   └── jobs.ts       # node-cron-registrering (startas i hooks.server.ts)
│   │   ├── client/
│   │   │   ├── api.ts        # fetch-wrapper: skickar mutationer via outbox
│   │   │   ├── outbox.ts     # IndexedDB-kö + replay vid reconnect
│   │   │   ├── mirror.ts     # IndexedDB-spegel av shopping/todos
│   │   │   ├── sse.ts        # EventSource med backoff-reconnect
│   │   │   └── stores.ts     # svelte stores: user, shopping, todos, events, activity, online
│   │   └── components/       # se §12
│   ├── routes/
│   │   ├── +layout.svelte    # bottom nav, FAB, UndoToast, banners
│   │   ├── +page.svelte      # Hem
│   │   ├── login/+page.svelte
│   │   ├── kalender/+page.svelte
│   │   ├── inkop/+page.svelte
│   │   ├── todo/+page.svelte
│   │   ├── installningar/+page.svelte
│   │   └── api/              # +server.ts-endpoints enligt §7
│   ├── hooks.server.ts       # session-resolve, jobbstart, säkerhetsheaders
│   └── service-worker.ts
├── static/manifest.webmanifest
├── .env.example
└── tests/
```

## 4. Miljövariabler (`.env.example`)

```
DATABASE_PATH=./dev.db
APP_ENCRYPTION_KEY=            # 32 byte base64 – genereras per miljö
SESSION_TTL_DAYS=180
CALDAV_SERVER=https://caldav.icloud.com
CALDAV_CALENDAR_NAME=Gemensamt-test   # prod: Gemensamt
VAPID_PUBLIC_KEY=
VAPID_PRIVATE_KEY=
VAPID_SUBJECT=mailto:dev@example.com
PUBLIC_APP_NAME=Planeraren
TZ_DEFAULT=Europe/Stockholm
SYNC_INTERVAL_MINUTES=5
```

Dev och prod skiljer sig ENDAST via env (separat DB-fil, separat testkalender).

## 5. Databas

Schemat i `db/schema.sql` är normativt. Nyckelpunkter implementationen MÅSTE
respektera:

- **Alla id:n för shopping/todos/events är klientgenererade UUID v4** (offline-idempotens).
- **Tidsatta event**: `start_ts`/`end_ts` i UTC ISO-8601. **Heldagsevent**:
  `start_date`/`end_date` som rena datum, `end_date` EXKLUSIVT. CHECK-constraint
  tvingar exakt en representation. Konvertera ALDRIG heldagar till midnatt-UTC.
- **Soft delete överallt** (`deleted_at`/`deleted_by`); hård radering endast via städjobbet.
- **`version`** på shopping/todos ökas med 1 vid varje UPDATE (görs i API-lagret, i samma transaktion).
- **`name_norm`** = `name.trim().toLowerCase()` – sätts alltid server-side.
- Partiellt unikt index på aktiva inköpsvaror = dubblettskyddet. Fånga
  `SQLITE_CONSTRAINT` och hantera enligt §7.3.
- Skriv en rad i `activity_log` i SAMMA transaktion som varje mutation.

## 6. Auth och sessioner

- Login: `POST /api/auth/login` med `{ username, password }` (username = `users.id`).
  Verifiera argon2. Skapa slumpad token (32 byte), lagra `sha256(token)` i
  `sessions`, sätt cookie `session` = råtoken: `HttpOnly; Secure; SameSite=Lax;
  Path=/; Max-Age=SESSION_TTL_DAYS`.
- `hooks.server.ts` slår upp sessionen på varje request, sätter `locals.user`,
  uppdaterar `last_seen_at` (max 1 ggr/timme). Alla `/api/*` utom login kräver user → annars 401.
- CSRF: mutationer kräver headern `X-Requested-With: fetch` (klientens api-wrapper
  sätter den alltid); saknas den → 403. Detta + SameSite=Lax räcker för v1.
- Rate limit på login: max 10 försök / 15 min per IP (enkel in-memory-räknare).

## 7. API-kontrakt

### 7.1 Konventioner

- Bas: `/api`, JSON in/ut. Datum/tider i UTC ISO-8601; rena datum som `YYYY-MM-DD`.
- Felformat: `{ "error": { "code": string, "message": string, ...extra } }`
  Koder: `unauthorized`, `forbidden`, `not_found`, `validation`,
  `version_conflict`, `duplicate`, `caldav_conflict`, `caldav_unavailable`.
- **Idempotens:** `POST` av en resurs vars klient-id redan finns → `200` med
  befintlig resurs (inte 409, inte dubblett). Det gör offline-replay säker.
- **Optimistisk låsning:** `PATCH` på shopping/todos kräver fältet `version`.
  Om `version != db.version` → `409 version_conflict` med `{ current: <hela raden> }`.
  Klienten skriver om sin vy med `current` och visar diskret "Uppdaterades av <namn>".
- Varje lyckad mutation: (1) activity_log-rad, (2) notification_queue-rad till
  DEN ANDRA användaren (se §11), (3) `broadcast()` via SSE (se §10) – allt i/direkt efter transaktionen.

### 7.2 Endpoints – auth/meta

| Metod & path | Beskrivning |
|---|---|
| `POST /api/auth/login` | Se §6. Svar: `{ user }` |
| `POST /api/auth/logout` | Raderar session + cookie |
| `GET /api/me` | `{ user, partner, prefs, syncStatus: { last_synced_at, failing_since } }` |

### 7.3 Inköp

| Metod & path | Beskrivning |
|---|---|
| `GET /api/shopping` | Aktiva varor (ej arkiverade/raderade), avbockade sist. |
| `GET /api/shopping/suggest?q=mj` | Autocomplete ur historiken: `SELECT name, COUNT(*) c, MAX(created_at) m FROM shopping_items WHERE name_norm LIKE :q || '%' GROUP BY name_norm ORDER BY c DESC, m DESC LIMIT 8`. Utan `q`: topp 8 vanligaste. |
| `POST /api/shopping` | Body `{ id, name, qty? }`. Vid dubblettkonflikt (partiella indexet): returnera `200` med den BEFINTLIGA aktiva varan + `"merged": true`. UI visar "Fanns redan på listan". |
| `PATCH /api/shopping/:id` | Body `{ version, checked?, name?, qty? }`. `checked: true` sätter `checked_by/checked_at`; `false` nollar dem. Namnbyte räknar om `name_norm` (kan ge dubblettkonflikt → `409 duplicate`). |
| `POST /api/shopping/archive-checked` | Sätter `archived_at` på alla avbockade. Loggas som EN activity-rad med antal. |
| `DELETE /api/shopping/:id` | Soft delete. |
| `POST /api/shopping/:id/restore` | Nollar `deleted_at` (ångra). Kan ge dubblettkonflikt → `409 duplicate` (varan hann läggas till igen); UI: "Finns redan". |

### 7.4 Todos

| Metod & path | Beskrivning |
|---|---|
| `GET /api/todos?filter=open\|done` | Öppna: deadline-satta först (stigande), sedan created_at fallande. Klara: done_at fallande, max 30 dgr. |
| `POST /api/todos` | `{ id, title, notes?, assignee?, due_date? }`. `assignee`: users.id, `"both"` eller null. |
| `PATCH /api/todos/:id` | `{ version, ... }`. `done: true` sätter `done_by/done_at`. |
| `DELETE /api/todos/:id` + `POST /api/todos/:id/restore` | Som inköp. |

### 7.5 Kalender

| Metod & path | Beskrivning |
|---|---|
| `GET /api/events?from=YYYY-MM-DD&to=YYYY-MM-DD` | Ur cachen. Overlap-query enligt kommentaren i schema.sql (tidsatta OCH heldagar, unionerade). Svar normaliserat: `{ id, title, allDay, start, end, location, createdBy, isRecurring }` där start/end är ISO-ts eller rent datum beroende på `allDay`. |
| `POST /api/events` | `{ id, title, allDay, start, end, location?, notes? }`. Validera: `end > start`; heldag → rena datum, end exklusivt. Skriver till CalDAV (§9.4) och cachen. CalDAV nere → `502 caldav_unavailable`, INGET sparas. **Eventmutationer köas ALDRIG offline i v1.** |
| `PATCH /api/events/:id` | Kräver inte `version` – konfliktkontrollen är CalDAV-etag (§9.4). Vid 412 från iCloud → `409 caldav_conflict` med `{ current }` (färsk kopia efter resynk av just det eventet). |
| `DELETE /api/events/:id` | Soft delete lokalt + DELETE mot CalDAV med `If-Match`. |
| `POST /api/events/:id/restore` | Åter-PUT av `raw_ics` till CalDAV, nollar `deleted_at`. |

### 7.6 Övrigt

| Metod & path | Beskrivning |
|---|---|
| `GET /api/activity?limit=30&before=<id>` | Rårader, nyast först. Gruppering görs i klienten (§12.2). |
| `GET /api/sync/status` | `{ last_synced_at, failing_since, last_error }` |
| `POST /api/sync/run` | Triggar en synkrunda direkt (pull-to-refresh, dev). |
| `POST /api/caldav/setup` | `{ appleId, appPassword }` → discovery (§9.1) → `{ calendars: [{ href, name }] }`. Sparar INGET ännu. |
| `POST /api/caldav/select` | `{ appleId, appPassword, href }` → krypterar och sparar på `locals.user`. |
| `POST /api/push/subscribe` | `{ endpoint, keys: { p256dh, auth } }` |
| `DELETE /api/push/subscribe` | Body `{ endpoint }` |
| `PATCH /api/push/prefs` | `{ enabled?, quiet_from?, quiet_to?, digest_minutes? }` |
| `GET /api/stream` | SSE, se §10. |

## 8. Aktivitetslogg – regler

`logActivity(type, actor, entityType, entityId, payload)` anropas i samma
transaktion som mutationen. Typkatalog (sluten lista v1):

```
shopping.added | shopping.checked | shopping.unchecked | shopping.deleted
shopping.restored | shopping.archived            (payload: {name} eller {count})
todo.created | todo.done | todo.undone | todo.deleted | todo.restored  ({title})
event.created | event.updated | event.deleted | event.restored         ({title, start})
```

Kalenderändringar som upptäcks via SYNK (gjorda i Apple Kalender) loggas INTE i
activity_log v1 – bara ändringar gjorda i appen. (Synk vet inte säkert vem som
gjorde vad; hellre tyst än fel attribution.)

## 9. CalDAV-synkmotor

### 9.1 Onboarding/discovery
1. `tsdav.createDAVClient` mot `CALDAV_SERVER` med Basic auth (Apple-ID + app-lösenord).
2. Hämta kalenderlistan (`fetchCalendars`), returnera `{ href, displayName }` för
   alla med komponentstöd VEVENT.
3. Användaren väljer kalendern vars namn matchar `CALDAV_CALENDAR_NAME` (UI
   förmarkerar den). Href + krypterade credentials sparas på användaren.

### 9.2 Pollloop (var `SYNC_INTERVAL_MINUTES` minut)
- Kör EN synkrunda per unik `caldav_calendar_href`, med credentials från den
  första användaren vars synk inte failar; faller tillbaka på den andra.
  (Upserts är idempotenta på `(caldav_uid, recurrence_id)` så dubbelkörning är ofarlig, bara onödig.)
- Använd `sync-collection`-REPORT med sparad `sync_token`. Vid ogiltig token
  (HTTP 410 eller iCloud-fel) → full omsynk: `calendar-query` för fönstret
  **[idag − 60 dgr, idag + 365 dgr]** och ersätt cachen för det fönstret.
- Ändrade resurser: hämta ICS, parsa, upserta (§9.3). Raderade (404 i report):
  **hårdradera** cache-raderna (extern radering ska inte gå att "ångra" i appen).
- Efteråt: uppdatera `sync_state` (token, `last_synced_at`, nolla
  `failing_since`). Vid fel: sätt `last_error`, sätt `failing_since` om NULL.
  Broadcast `changed:events` via SSE om något ändrades.

### 9.3 ICS → events-rader (`ics.ts`)
- Parsa med `ical.js`. För varje VEVENT:
  - `DTSTART`/`DTEND` av typ DATE → heldag: `start_date`, `end_date` (exklusivt;
    saknas DTEND → end_date = start_date + 1 dag). Typ DATE-TIME → konvertera
    till UTC med eventets TZID → `start_ts`/`end_ts` (saknas DTEND → +1 h).
  - RRULE: expandera förekomster i fönstret **[idag − 30 dgr, idag + 180 dgr]**
    med `ICAL.RecurExpansion` (respektera EXDATE och overrides med
    RECURRENCE-ID). En rad per förekomst; `recurrence_id` = förekomstens
    starttid (ISO) resp. `''` för icke-återkommande.
  - Spara `raw_ics` (hela VCALENDAR-objektet för resursen), `etag`, `caldav_href`.
  - `created_by`: matcha eventets UID mot prefix `app-<userid>-` (se §9.4);
    annars NULL.
- Upsert-nyckel: `(caldav_uid, recurrence_id)`. Befintlig rad behåller sitt `id`.

### 9.4 Skrivflöde (`write.ts`)
- **Create:** UID = `app-<userid>-<uuid>` (ger `created_by` gratis vid återsynk).
  Bygg minimal VCALENDAR/VEVENT (DTSTART/DTEND/SUMMARY/LOCATION/DESCRIPTION;
  heldag = VALUE=DATE). `PUT` med `If-None-Match: *`. Läs tillbaka etag
  (via HEAD/GET eller multiget) och spara cacheraden direkt – vänta inte på nästa pollrunda.
- **Update:** utgå från `raw_ics`, mutera ENDAST de fält användaren ändrat,
  serialisera om (bevarar VALARM, ATTENDEE m.m. som appen inte modellerar).
  `PUT` med `If-Match: <etag>`. **HTTP 412** → hämta färsk resurs, upserta
  cachen, svara `409 caldav_conflict` med `current` (klienten visar om formuläret).
  Uppdatering av en ENSKILD förekomst av återkommande event stöds EJ i v1 →
  `422 validation` med förklarande message; hela serien kan dock raderas.
- **Delete:** `DELETE` med `If-Match`. 412 → som ovan. Lyckas → soft delete i
  cachen (ångra-fönster). **Restore:** `PUT` av `raw_ics` med `If-None-Match: *`, nolla `deleted_at`.

## 10. Realtid (SSE)

- `GET /api/stream`: håll anslutningen öppen, skicka heartbeat-kommentar var 25 s.
- `broadcast(entityType)` skickar `event: changed\ndata: {"entity":"shopping"}` till
  ALLA anslutna UTOM avsändarens egen anslutning (klienten skickar sitt
  connection-id som query-param; egen vy uppdateras redan optimistiskt).
- Klient: `EventSource` med exponentiell backoff-reconnect (1 s → max 30 s).
  Vid `changed` → refetch:a berörd lista. Vid reconnect → refetch:a allt + kör outbox-replay.

## 11. Notiser

- Vid mutation: lägg en rad i `notification_queue` med `recipient = partnern`,
  `send_after = now + prefs.digest_minutes`.
- Worker (varje minut): hämta osända rader med `send_after <= now`, grupperade
  per mottagare. Hoppa över om mottagarens `enabled = 0` eller inga
  prenumerationer finns. **Tysta timmar:** om mottagarens lokala tid
  (`TZ_DEFAULT`) ligger i `[quiet_from, quiet_to)` → flytta radernas
  `send_after` till nästa `quiet_to` och fortsätt.
- Digesttext från de grupperade activity-raderna, max 3 exempel + räknare:
  `"Anna: la till Mjölk, Bröd + 2 till · bockade av Boka besiktning"`.
  Skicka EN push per mottagare via `web-push`. HTTP 404/410 från push-tjänsten →
  sätt `failed_at` på prenumerationen. Markera raderna `sent_at`.
- Notisklick öppnar appen på Hem.

## 12. Frontend

### 12.1 Global UX
- **Bottom nav:** Hem · Kalender · Inköp · Att göra (ikoner + text, aktiv flik
  markerad med användarfärg). **FAB** i mitten: öppnar sheet med tre val →
  Nytt event / Ny vara / Ny uppgift, oavsett aktiv vy.
- **UndoToast (global):** varje destruktiv åtgärd (delete, archive-checked,
  bocka av todo) visar toast 6 s med "Ångra". Ångra anropar restore-endpointen.
  Åtgärden utförs OMEDELBART (ingen väntan på toast-timeout).
- **Banners i layouten:** (1) offline: "Du är offline – ändringar sparas och
  synkas sen", (2) `failing_since` > 1 h: "Kalendersynken har problem sedan HH:MM –
  kontrollera lösenordet i Inställningar".
- **Optimistisk UI:** alla mutationer skriver spegeln/storen först, sedan API.
  Vid 4xx-svar: rulla tillbaka + visa felmeddelande.
- Färgkodning: allt innehåll får en liten avatarprick i skaparens/utförarens färg.
- Svenskt UI. Tidszon för visning: `TZ_DEFAULT`.

### 12.2 Vyer
- **Hem:** sektion "Idag" = dagens events (heldagar överst, sedan tidsordning)
  + todos med deadline idag/försenade. Efter kl 18: extra sektion "Imorgon".
  Sektion "Nyligen" = activity-raderna grupperade: samma aktör + entity_type
  inom 30 min slås ihop till en rad ("Anna la till 3 varor · 20 min sedan").
  Egen aktivitet visas som "Du …".
- **Kalender:** agenda-lista grupperad per dag, rullande 4 veckor framåt +
  1 vecka bakåt, infinite scroll. Flerdagarsevent visas under VARJE berörd dag
  med suffix "(dag 2 av 3)". Tap → detaljsheet med Redigera/Radera.
  Eventformulär: titel, heldagstoggle (växlar datum- vs datetime-fält),
  start/slut, plats, anteckningar. Månadsgrid är INTE med i v1.
- **Inköp:** inputfält överst med förslagschips (från `/suggest`, visas vid
  fokus och medan man skriver). Aktiva varor överst, avbockade genomstrukna
  under. Tap = bocka av/på. Swipe vänster (eller långtryck-meny) = radera.
  Knappen "Töm avklarade" visas när ≥ 1 avbockad finns. `merged: true`-svar →
  liten toast "Fanns redan på listan".
- **Att göra:** filterpills Alla/Du/[Partner]/Gemensamt. Öppna överst enligt
  §7.4-sortering, hopfällbar "Klart"-sektion. Formulär: titel, anteckningar,
  ansvarig (segmentkontroll), valfri deadline.
- **Inställningar:** synkstatus ("Senast synkad 14:32" + manuell synk-knapp),
  CalDAV-wizard (två steg enligt §7.6), notisinställningar (toggle, tysta
  timmar, digest), iOS-installationsguide ("Lägg till på hemskärmen" – krävs
  för push), logga ut.
- **Login:** användarval (två knappar med namn/färg) + lösenord.

### 12.3 Offline & PWA
- `vite-plugin-pwa`: precache appskal; manifest med namn, ikoner, `display: standalone`.
- **Spegel (`mirror.ts`):** shopping + todos + senaste activity + events för
  synligt fönster lagras i IndexedDB efter varje lyckad GET. Vid appstart:
  rendera ur spegeln direkt, refetch:a i bakgrunden.
- **Outbox (`outbox.ts`):** när `navigator.onLine` är false (eller fetch
  nätverksfailar) läggs mutationen i IndexedDB-kön istället. Vid reconnect:
  spela upp FIFO. Idempotens via klient-uuid gör dubbelreplay ofarlig.
  **Konfliktregel vid replay:** svar 409/`duplicate`/`version_conflict` →
  släng den köade mutationen, refetch:a listan (server vinner). Inga dialoger.
  Eventmutationer går ALDRIG i outbox (§7.5) – FAB:ens eventval disablas offline.

## 13. Bakgrundsjobb (`jobs.ts`, startas en gång i `hooks.server.ts`)

| Jobb | Schema | Gör |
|---|---|---|
| CalDAV-synk | var 5:e min (`SYNC_INTERVAL_MINUTES`) | §9.2 |
| Notis-worker | varje minut | §11 |
| Städning | dagligen 04:00 | Purge-listan i schema.sql:s slutkommentar |
| Sessionsstäd | dagligen 04:10 | `DELETE FROM sessions WHERE expires_at < now` |

Jobben får inte överlappa sig själva (enkel `isRunning`-flagga per jobb).

## 14. Säkerhet

- Cookies enligt §6. Alla svar: `X-Content-Type-Options: nosniff`,
  `Referrer-Policy: same-origin`, CSP minst `default-src 'self'`.
- CalDAV-credentials: AES-256-GCM med `APP_ENCRYPTION_KEY`, unik IV per post,
  authtag lagras med ciphertexten. Credentials loggas ALDRIG; felmeddelanden
  från CalDAV saneras innan de sparas i `sync_state.last_error`.
- App-lösenordet skickas från klienten endast i setup-anropen (§7.6) över HTTPS
  och returneras aldrig.
- Ingen användargenererad HTML någonstans – allt renderas som text.

## 15. Teststrategi (vitest)

- **`ics.ts` (viktigast):** fixturfiler med (a) tidsatt event med TZID,
  (b) heldag en dag, (c) heldag flera dagar (verifiera exklusivt slut),
  (d) tidsatt över midnatt, (e) RRULE veckovis med EXDATE, (f) RRULE med
  override (RECURRENCE-ID). Verifiera mappning åt båda håll (parse → rad,
  rad → serialisering som bevarar okända fält).
- **API-integration** (in-memory SQLite, schema.sql körd): dubblettflödet
  (POST samma name_norm två ggr → merged), version_conflict-flödet,
  idempotent POST med samma id, restore-med-dubblettkrock, archive-checked.
- **Notiser:** enhetstest av tysta timmar-beräkningen och digestgrupperingen.
- **Overlap-queryn:** heldag + tidsatt + flerdagars mot en given dag.

## 16. Byggordning med acceptanskriterier

**M1 – Stomme.** Projekt, DB-setup (migrate + seed), auth, layout med bottom
nav/FAB (tomma vyer), PWA installerbar. ✓ Klart när: båda testanvändarna kan
logga in på mobil, installera appen på hemskärmen och navigera mellan flikar.

**M2 – Listor + flöde.** Inköp, todos, activity_log, hemskärmens båda
sektioner (utan events), ångra-toast, dubblettmerge, autocomplete, SSE.
✓ Klart när: två inloggade enheter ser varandras ändringar inom 5 s; radering
kan ångras; "mjölk" två gånger ger en vara; testfallen i §15 (API) är gröna.

**M3 – Offline.** Spegel + outbox + replay + offlinebanner. ✓ Klart när:
flygplansläge → appen öppnas med data, varor kan bockas av, och allt synkas
korrekt (utan dubbletter) när nätet är tillbaka.

**M4 – Kalender läs.** CalDAV-wizard, pollsynk, kalendervyn, "Idag" på hem,
synkstatus + felbanner. ✓ Klart när: event skapat i Apple Kalender
(testkalendern) syns i appen inom 5 min; heldag/flerdagars/återkommande
renderas rätt dag; fel lösenord ger banner, inte krasch; §15 ics-testerna gröna.

**M5 – Kalender skriv.** Skapa/redigera/radera/ångra från appen med
etag-hantering. ✓ Klart när: event skapat i appen dyker upp på iPhone; en
ändring gjord i Apple Kalender medan appens formulär är öppet ger
caldav_conflict-flödet (inte tyst överskrivning); ångrad radering återuppstår i iCloud.

**M6 – Notiser + polish.** Web push med digest och tysta timmar,
pull-to-refresh-synk, tomvyer, felstates. ✓ Klart när: en ändring på enhet A
ger EN samlad notis på enhet B efter digestfönstret, och ingen notis under tysta timmar.

## 17. Icke-mål v1 (bygg INTE)

Flera inköpslistor eller kategorier · månadsgrid · redigering av enskilda
förekomster i återkommande serier · larm/inbjudningar på event · free/busy mot
privata kalendrar · fler än två användare/multi-tenant · återkommande todos ·
delning/export · native-appar. Registrering av nya konton sker aldrig via UI.
