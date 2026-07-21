# DECISIONS.md

Logg över val gjorda där IMPLEMENTATION_SPEC.md är tyst.
Format: `ÅÅÅÅ-MM-DD · beslut · motivering (en rad)`

<!-- Exempel:
2026-07-21 · Valde X framför Y i Z · enklast som uppfyller M2-kriterierna
-->

2026-07-21 · Dev-lösenordshash sätts i migrate.ts seed-steget (argon2 av 'devlosen') · Placeholder-hashen i seed.dev.sql (normativ, orörd) matchar varken 'devlosen' eller 'password', så login vore omöjligt. Seed-filen uppmanar själv till egen hash i seed-pipelinen; argon2 följer spec §2/§6 och undviker nytt beroende.
2026-07-21 · Login verifierar endast argon2 · Enda hashar som existerar sätts nu via seed-pipelinen (argon2). Enklast och spec-enligt; ingen bcrypt-fallback behövs.
2026-07-21 · Login-sidans användarlista (namn/färg) hämtas via login/+page.server.ts, inte ett publikt API · Specen är tyst om hur de två knapparna fylls; server-load undviker en ny oautentiserad endpoint.
2026-07-21 · Inställningar nås via en kugghjulsikon i toppbaren · Bottom nav har bara Hem/Kalender/Inköp/Att göra (spec §12.1); toppbaren ger plats åt Inställningar.
2026-07-21 · PWA: vite-plugin-pwa generateSW · Enklast installerbara appskal; byts till injectManifest i M6 när push kräver egen service worker.
2026-07-21 · devOptions.enabled=false (SW körs ej i dev) · Dev-SW:n cachade navigeringar och krockade med SSR-auth-guarden. Installerbarhet verifierad i M1; SW/offline testas via build+preview och konfigureras korrekt i M3.
2026-07-21 · Lade till POST /api/shopping/unarchive · §12.1 kräver ångra på "Töm avklarade" men §7.3 saknar av-arkiveringsendpoint. Minsta tillägg som uppfyller UX-kravet; loggar ingen activity (ingen passande typ i den slutna katalogen §8).
2026-07-21 · Tjänstelager (shopping.ts/todos.ts/activity.ts) tar db som argument · Gör API-logiken testbar mot in-memory-SQLite (spec §15) utan $env/$app; endpoints är tunna wrappers.
2026-07-21 · Skapa nytt (FAB) är globala sheets i layouten, styrda av createKind-store · Uppfyller "oavsett aktiv vy" (§12.1) utan navigering; listvyerna läser samma stores.
2026-07-21 · CalDAV-synk använder full calendar-query för fönstret [−60d, +365d] varje runda i stället för inkrementell sync-collection-token · §9.2:s egen fallback; idempotent på (caldav_uid, recurrence_id) och billig för en 2-personerskalender. Vald för robusthet eftersom sync-token-vägen inte kan testas mot iCloud här. Uppfyller acceptanskravet "syns inom 5 min".
2026-07-21 · Timestamps från SQLite datetime('now') normaliseras till ISO-UTC (toIso) innan de skickas till klienten · datetime('now') saknar Z och tolkas som lokal tid av webbläsaren → tidsförskjutning. Inserts använder fortfarande DB-defaults så SQL-sortering är konsekvent.
2026-07-21 · App-skapade events får server-genererat cache-id (inte klient-uuid) · CalDAV är master för kalendern; sync genererar id vid första upsert. Events köas aldrig offline så klient-id behövs inte för idempotens.
2026-07-21 · Egen service worker via injectManifest (src/service-worker.ts) · Push kräver egen SW. Behåller NetworkFirst-navigering + precache från M3 och lägger till push/notificationclick. generateSW-workboxblocket ersatt.
2026-07-21 · Tjänstelagrets rena logik ligger i egna moduler utan $env/DB (sqlite-util, notify-util, http via web-Response) · Så att API-, ics-, agenda- och notislogik kan enhetstestas i vitest utan SvelteKit-plugin. 41 tester totalt.
2026-07-21 · todos.start_date läggs till via runtime-migrering i db.ts (ALTER TABLE om kolumnen saknas), schema.sql orörd · Användaren bad om perioduppgifter ("gör inom X–Y"); schema.sql är normativ så kolumnen appliceras vid DB-öppning + speglas i testhelpern. Perioder visas på Hem endast på sista dagen (due_date); start_date är informativ (badge i Att göra).
2026-07-21 · Hem-flödet visar endast shopping.added/shopping.checked · Användarbeslut: "behöva köpa och köpt är det enda viktiga". Övriga händelser finns kvar i activity_log (driver notiser) men renderas inte på Hem.
2026-07-21 · Hem = delad vy (dag ovan / inköpshistorik nedan) med draggbar delare · Delaren återställs till 50/50 vid varje navigering till Hem (komponent-remount). Dagsbyte via swipe + chevron-knappar, klampat till eventfönstret −7..+42 dagar.
