# Native-spike: kan två personer få en delad kalender smidigt?

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
