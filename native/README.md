# HouseMates native

MVP (2026-10-05): inloggning, hushåll för två, delad inköpslista i realtid, delad kalender via
iPhonens egen kalender (väg A nedan) och notiser till partnern. SwiftUI-app i `app/`, eget
Supabase-projekt i `supabase/`. Webbappen och dess databas påverkas inte.

## Kom igång lokalt

1. Starta den lokala databasen (portarna 553xx, krockar inte med webbappens):
   ```bash
   cd native && supabase start -x analytics,imgproxy,studio,vector,meta,storage
   ```
2. Bygg appen: `cd native/app && xcodegen generate && open HouseMates.xcodeproj` och kör på en
   simulator. `Config/Local.xcconfig` pekar på den lokala databasen.
3. Skapa konto i appen, tryck "Skapa hushåll" och lägg till varor.
4. Spela partnern från terminalen, så räcker en simulator:
   ```bash
   node native/supabase/partner.mjs join <din-epost>
   ```
   `partner.mjs add <vara>` och `partner.mjs check <vara>` ändrar listan som "Anna";
   ändringen syns direkt i appen.
5. Se vilka notiser som skulle skickas (torrt, utan APNs-nyckel):
   ```bash
   (cd native && supabase functions serve --env-file supabase/functions/.env)
   ```
   `supabase/functions/.env` behöver raden `CRON_SECRET=lokal-hemlighet`. Kör sedan
   `node native/supabase/notify-check.mjs` i en annan terminal.

Behörigheter, triggers och notiskö testas med `node native/supabase/smoke.mjs` (19 kontroller
mot den lokala databasen). APNs-signeringen testas i `tests/apns.test.ts` (`npm test`).

## Hur det hänger ihop

- **Inloggning:** e-post och lösenord (Supabase Auth). Namnet sparas i `profiles`.
- **Hushåll:** den ena skapar, den andra går med med en sexteckenskod. Max två medlemmar.
  Alla tabeller bär `household_id`, och RLS släpper bara igenom det egna hushållet.
- **Inköp:** `shopping_items`. Appen visar ändringar direkt och skickar dem sedan. Realtid
  hämtar om listan när partnern ändrar något. Samma vara kan bara stå en gång (unikt index).
- **Kalender:** finns bara i telefonerna (EventKit). Den som sätter upp väljer en delad
  kalender eller skapar en ny. Kalenderns titel och UID för några händelser sparas i
  `households`, så partnerns app hittar samma kalender själv. Händelser skapas och ändras i
  Apples egen redigeringsvy.
- **Notiser:** varje ändring skriver en rad i `activity_log` i samma transaktion (trigger). För
  kalendern rapporterar appen sina ändringar via `log_calendar_activity`. Raden köas till
  partnern. Edge function `notify` körs varje minut (`supabase/cron.sql`) och skickar EN samlad
  notis när det varit tyst i tre minuter. Det är samma digest som webbappen. Ett tryck på
  notisen öppnar rätt flik.
- **Radera konto:** `delete_account()` tar bort inloggningen. Profil, medlemskap, push-token,
  egen historik och väntande notiser följer med (`on delete cascade`).
  - Den som är sist kvar i hushållet tar hushållet och listan med sig.
  - Annars blir listan kvar för partnern, utan koppling till personen.
  - Appen rensar sedan allt den sparat på telefonen.
  - Kalendern i Apple Kalender rörs inte. Den ligger i iCloud och kan vara delad med partnern.

## Verifierat i simulatorn (2026-10-05)

- skapa konto → skapa hushåll → partnern går med via koden
- lägga till, bocka av, radera och tömma varor
- partnerns ändringar syns i appen inom 1,5 s (realtid), och "Töm" ger ingen notis
- kalender: förklaring med "Fortsätt" → systemdialog → välj kalender → kopplingen sparas på
  servern → ny händelse i Apples redigeringsvy → notistext "William la in Middag med Erik i
  kalendern / mån 5 okt. 15:00"
- partnern loggar in och kopplas automatiskt till samma kalender via UID:n
- en telefon som saknar hushållets kalender visar vänteläget; att välja fel kalender själv
  ger en varning
- en inloggning vars konto har raderats loggas ut i stället för att fastna
- radera konto, både ensam i hushållet (hushåll och lista raderas) och med partner (listan
  blir kvar för partnern, utan koppling till personen), och innan man har ett hushåll
- push: bannern visas med rätt svensk text (simulerad leverans med `simctl push`)

**Inte verifierat:**
- att ett tryck på notisen öppnar rätt flik (simulatorns notiscenter tog inte emot tryck
  från testverktyget)
- riktig APNs-leverans (kräver nyckel)
- två fysiska telefoner med iCloud-delning

## Kvar före TestFlight och App Store

1. **Betalt Apple Developer-konto.**
   - Slå på Push Notifications för `se.housemates.app` och ladda ner en APNs-nyckel (.p8).
   - Sätt secrets på det hostade projektet: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`
     (innehållet i .p8-filen), `APNS_BUNDLE_ID=se.housemates.app` och `CRON_SECRET`.
     Lägg till `APNS_PRODUCTION=true` för TestFlight och App Store.
   - Lägg till `aps-environment` i appens entitlements.
2. **Hostat Supabase-projekt.**
   - Kör `supabase link` och `supabase db push`, deploya `notify` och kör `cron.sql`.
   - Lägg till en `Config/Release.xcconfig` med projektets adress och nyckel.
3. **Integritetspolicy:** en länk i appen och i App Store Connect. Beskriv där vad
   "Radera konto" tar bort.
4. **Granskningsanteckningar:** förklara varför full kalenderåtkomst behövs och hur
   granskaren testar.
5. **Senare:**
   - lämna hushåll
   - tysta timmar för notiser
   - flytta in er befintliga data

# Spike: kan två personer få en delad kalender smidigt?

Branch `feat/native`, 2026-10-03. Frågan som avgör native-satsningen: går det att sätta upp
en delad kalender mellan två personer i en App Store-app utan Apple-ID, appspecifikt
lösenord eller krångel?

## Svar i korthet

- **Helt automatiskt: nej.** Ingen app kan dela en Apple-kalender åt användaren. EventKit
  (iOS 26.5 SDK) saknar API för delning, inbjudningar och för att läsa om en kalender är
  delad. Apple har ingen öppen OAuth för iCloud-kalender. Det finns inte heller någon
  dokumenterad djuplänk till Kalender-appens delningsvy.
- **Smidigt nog: ja, på två sätt.**
  - **A: iCloud-delning.** Ni väljer en kalender ni redan delar, eller skapar en ny och
    delar bara den, en gång, i Apples egen vy.
  - **B: egen kalender + prenumeration.** Delningen sker via en inbjudningslänk i appen.
- **C (egen CalDAV-server via profil) är avfärdad**, och **D (spegling via tyst push) är
  för skör** som första steg.

## Vägarna

### A · iCloud-delning: välj er delade kalender eller skapa en ny (EventKit)

Bara en kalender delas med partnern, aldrig alla.

- **Per person:** ett tryck på "Tillåt full åtkomst".
  - iOS har ingen behörighet för en enskild kalender: läsning kräver full åtkomst
    (`EKAuthorizationStatusFullAccess`, "read or modify all data"). Appen läser och skriver
    ändå bara den valda kalendern, och det står i behörighetstexten.
  - Dialogen i iOS 26 visar en händelse ur användarens kalender och antalet händelser
    ("52 aktiviteter nästa år"). Förklara därför i appen innan dialogen visas.
- **Den som sätter upp väljer** en kalender ni redan delar, eller trycker "Skapa ny
  HouseMates-kalender". Den nya kalendern hamnar i iCloud.
  - Om kalendern inte redan är delad visar appen en guide: Kalender → Kalendrar → ⓘ →
    Lägg till person → välj partnern → Lägg till. Det blir cirka 6 tryck plus att välja
    kontakt. Steget kan inte automatiseras eller djuplänkas.
  - Appen skickar en *kopplingskod* till partnern via Meddelanden. Koden är en text med en
    länk inuti.
- **Kopplingskoden innehåller bara id:n:** kalenderns titel och UID för upp till fem
  kommande händelser i den. Inget innehåll följer med.
  - **Befintlig kalender med händelser:** inget skrivs till den. Den kan vara delad med
    fler, till exempel familjen.
  - **Tom eller ny kalender:** appen skriver en *kopplingshändelse* ("HouseMates är
    kopplad"). Partnerns app raderar den automatiskt när den har hittat kalendern.
- **Partnern** accepterar kalenderinbjudan (cirka 2 tryck) och klistrar in koden. Appen
  slår upp varje UID med `calendarItems(withExternalIdentifier:)` och väljer kalendern
  med flest träffar.
  - Ingen träff betyder att inbjudan inte är accepterad ännu. Appen väntar och försöker igen
    när man kommer tillbaka.
  - Partnern kan också välja kalendern själv. Appen kontrollerar då UID:n och varnar om det
    inte är samma kalender.
- **Verifierat i simulatorn (KalenderTest):**
  - skapa en ny kalender: kopplingshändelse, kod och delningsguide
  - välja en befintlig kalender: "Kopplingskod från 3 befintliga händelser, inget skrevs"
  - klistra in koden: kalendern hittas och kopplingshändelsen raderas
  - vänteläge och manuellt val: varning vid fel kalender
  - en kalender som synkats in från en server hittas via UID och flaggas som skrivskyddad
  - `calendarItemExternalIdentifier` är exakt ICS-UID:t
- **Fynd som rättats i testappen:**
  - "Kopiera" i delningsbladet tog bara med texten och tappade en separat länk. Koden
    skickas därför som en enda text.
  - Systemknappar (Klistra in, Kopiera) blev engelska tills `developmentLanguage: sv` sattes.
- **Par som redan delar en iCloud-kalender** slipper delningssteget helt.
- **Synk:** Apples egen iCloud-push. Kalendern går att redigera överallt: Kalender-appen,
  Siri och widgets.
- **Servern:** ingen kalenderkod alls.
  - CalDAV-synkmotorn (`caldav-*`, `event-write`) och app-lösenorden försvinner.
  - Fältet "för vem" (assignee) kan inte skrivas som X-egenskap via EventKit. Det lagras i
    stället i en egen tabell nycklad på UID.
- **Begränsningar:**
  - Båda måste ha iCloud-kalender. Google fungerar också, men kräver delning via webben
    och syncselect.
  - Notis om kalenderhändelser skickas bara när ändringen görs i appen.

### B · Egen kalender + webcal-prenumeration

- **Delning:** samma inbjudningslänk som för hushållet, inga steg hos Apple.
- **Apple Kalender, uppmätt i simulatorn:** 3 tryck per person. Först "Lägg till i
  Kalender" i appen, sedan Sök och ✓ i Apples förifyllda blad. Titeln (`X-WR-CALNAME`) och
  händelserna visas direkt i förhandsvisningen.
- **Skrivskyddad i Apple Kalender.** Händelser skapas och ändras bara i appen. Så gör
  Cozi, FamilyWall och Cupla.
- **Färskhet, uppmätt:**
  - Kalender-appen hämtar flödet när den öppnas. En händelse som lades till 09:37:12
    fanns i telefonen 09:40:06, när Kalender öppnades.
  - Ny hämtning sker tidigast efter några minuter: två öppningar inom 25–75 s gav ingen
    ny hämtning.
  - Passiv bakgrundshämtning, utan att någon öppnade Kalender: en händelse som lades till
    09:42:21 fanns i telefonen 10:16:35. Det var cirka 36 minuter efter föregående hämtning.
    Simulatorn kör på en Mac med ström och wifi. En iPhone på batteri kan vara långsammare,
    eftersom "Automatiskt" enligt Apple bara hämtar vid laddning och wifi.
  - Enligt research ignorerar iOS `X-PUBLISHED-TTL`.
- **Servern:** en edge function som renderar ICS per hushåll med en hemlig token, cirka
  50 rader. CalDAV-synken försvinner även här.
- Fungerar för alla: Google, Outlook och Android.

### C · Egen CalDAV-server via konfigurationsprofil (avfärdad)

- **Uppmätt:** cirka 10 tryck plus lösenkod och en omväg via Inställningar. Två
  varningar om "Ej signerad" visas. Steg: Tillåt → Stäng → öppna Inställningar → Profil
  hämtad → Installera → Installera → Installera → Klar.
- **App Review, riktlinje 5.5 (läst ordagrant 2026-10-03):** MDM-appar "may only be offered
  by commercial enterprises, educational institutions, or government agencies" och "Apps
  offering configuration profiles must also adhere to these requirements". En
  konsumentapp som erbjuder en CalDAV-profil faller alltså utanför. Ett manuellt
  CalDAV-konto kräver i stället sex skärmar och att man skriver in server, användare och
  lösenord.
- **Tekniskt fullt möjligt:** lokalt släpper Supabase-gatewayen igenom OPTIONS, PROPFIND,
  REPORT, MKCALENDAR, PROPPATCH, PUT och DELETE, Basic-auth och `Depth` till en edge
  function. Det är onboardingen som fäller vägen.
- Simulatorn skapar inte CalDAV-kontot från profilen, och manuellt konto gick inte att spara.

### D · Egen kalender speglad in i telefonens kalender (för skör)

- Delning via inbjudningslänk och ett tryck för behörighet. Händelser kan redigeras i
  Apple Kalender.
- **Men** ändringar flyttas bara när appen kör. Tyst push som väcker appen garanteras inte
  av Apple, stryps och levereras inte om appen är tvångsstängd.
  - Gick inte att verifiera i simulatorn, eftersom `simctl push` levereras som vanlig
    notis och aldrig som bakgrundspush.
- Kräver en egen synkmotor på telefonen (konflikter, raderingar, återkommande händelser).

## Rekommendation

**Skrota inte idén.**

- **Bygg A som standardväg** för iPhone-par. Den tar bort de svåraste delarna av dagens
  lösning (app-lösenordet och CalDAV-synkmotorn) och behåller Apple Kalender som
  redigerbar master. Det manuella steget görs en gång och bara av par som inte redan delar
  en kalender.
- **B är reserven** för par utan iCloud och för Android senare. Den är också det enklaste
  att bygga om A:s delningssteg visar sig vara för krångligt i verkligheten.

**Beslutet hänger på ett test som bara går att göra på riktiga telefoner:** hur lång tid
tar delningen och partnerns accept i praktiken, och hittar partnerns telefon kalendern via
iCloud?

## Test på riktiga telefoner (cirka 15 min)

Appen läser och skriver bara den kalender ni väljer. Väljer ni "Skapa ny" skapas en
iCloud-kalender, "HouseMates", som kan raderas efteråt.

1. **Bygg och installera:** `cd native/kalendertest && xcodegen generate && open
   KalenderTest.xcodeproj`. Välj ditt team under Signing och kör på båda telefonerna.
   Ett gratis utvecklarkonto räcker.
2. **Telefon A:**
   1. Ge åtkomst.
   2. Välj er delade kalender, eller tryck "Skapa ny HouseMates-kalender". Kontrollera
      att källan är iCloud.
3. **Om kalendern är ny eller inte delad:** följ guiden i appen (Kalender → Kalendrar → ⓘ
   → Lägg till person). Notera antal tryck och tid.
4. **Telefon A:** "Skicka kopplingskod" → Meddelanden → partnern.
5. **Telefon B:**
   1. Acceptera kalenderinbjudan. Notera var den dök upp: notis, Inkorg eller e-post.
   2. Kopiera meddelandet, öppna KalenderTest, ge åtkomst och tryck "Klistra in".
   3. Förväntat resultat: "Kopplad till …". Om inbjudan inte var accepterad ska appen
      visa vänteläget och sedan koppla av sig själv när du kommer tillbaka från Kalender.
6. **Synktid:** tryck "Skriv testhändelse" på ena telefonen. På den andra visar "Senast
   ändrat" både "ändrad" och "syntes här"; skillnaden är synktiden.
7. **Ny kalender:** kopplingshändelsen ska försvinna från båda telefonerna.
8. **Valfritt, väg B på riktig telefon:** kör `BIND=0.0.0.0 server/start.sh` på Macen och
   prenumerera på `webcal://<macens-ip>:8787/feed.ics` i Safari.
   - Lägg till händelser med `curl -X POST <mac>:8787/events -d '{"title":"Test"}'`.
   - Notera när de dyker upp utan att Kalender-appen öppnas.

## Öppna frågor

- Hur ofta en riktig iPhone på batteri hämtar ett prenumererat flöde. Simulatorn hämtade
  det ungefär var 36:e minut.
- Om Family Sharing fortfarande skapar en delad "Familj"-kalender på iOS 26. I så fall är
  det noll delningssteg för par i samma familjegrupp, och kalendern väljs som vilken
  befintlig delad kalender som helst.

## Filer

- `kalendertest/` – SwiftUI-testapp för väg A (xcodegen):
  - `CalendarLink.swift`: välj eller skapa, kopplingskod, koppla, vänta, verifiera och
    synktest.
  - `LinkCode.swift`: kopplingskoden som länk eller text.
  - En kod kan öppnas från Macen med `xcrun simctl openurl <enhet>
    "kalendertest://koppla?titel=…&uid=…"`.
- Den tidigare testappen för alla fyra vägar (A–D) finns i git-historiken (commit
  `6fd51c2`, `native/spike/`).
- `server/` – testservrar för väg B och C:
  - `spike-server.mjs` (webcal-flöde, profil, `POST /events`). Den loggar varje hämtning
    av flödet, så att man ser när iOS uppdaterar.
  - Radicale som CalDAV-server.
  - `start.sh` startar båda.
