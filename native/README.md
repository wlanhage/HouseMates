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
  - **A: iCloud-delning med guide.** Delningen görs en gång, i Apples egen vy.
  - **B: egen kalender + prenumeration.** Delningen sker via en inbjudningslänk i appen.
- **C (egen CalDAV-server via profil) är avfärdad**, och **D (spegling via tyst push) är
  för skör** som första steg.

## Vägarna

### A · iCloud-delning med guide (EventKit)

- **Per person:** ett tryck på "Tillåt fullständig åtkomst".
- **Om appen:** den skapar kalendern "HouseMates" i iCloud via EventKit.
- **Ägaren** delar en gång i Kalender-appen: Kalendrar → ⓘ → Lägg till person → välj
  partnern → Lägg till. Det blir cirka 6 tryck plus att välja kontakt. Steget kan inte
  automatiseras eller djuplänkas, så appen visar en bildguide.
- **Partnern** öppnar inbjudan och trycker Gå med, cirka 2 tryck.
- **Partnerns app hittar kalendern själv** via en *kopplingshändelse*: en händelse med
  URL `housemates://koppling/<hushålls-id>`.
  - Verifierat i simulatorn: EventKit läser `url` och UID från serverns ICS.
  - `calendarItemExternalIdentifier` är exakt ICS-UID:t.
- **Par som redan delar en iCloud-kalender** slipper delningssteget helt. De väljer bara
  den befintliga kalendern.
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
tar A:s delning och partnerns accept i praktiken, och dyker kopplingshändelsen upp hos
partnern?

## Test på riktiga telefoner (cirka 15 min)

Testet skapar en ny iCloud-kalender, "HouseMates", som kan raderas efteråt. Er riktiga
kalender rörs inte.

1. `cd native/spike && xcodegen generate && open KalenderSpike.xcodeproj`. Välj ditt team
   under Signing och kör på båda telefonerna.
2. **Telefon A:**
   1. Ge kalenderåtkomst.
   2. Tryck "Skapa HouseMates-kalender" och kontrollera att källan är iCloud.
   3. Tryck "Skriv kopplingshändelse".
3. **Telefon A i Kalender-appen:** Kalendrar → ⓘ vid HouseMates → Lägg till person →
   partnern. Notera antal tryck och tid.
4. **Telefon B:** acceptera inbjudan. Notera var den dök upp: notis, Inkorg eller e-post.
5. **Telefon B:** öppna KalenderSpike → Ge åtkomst → "Hitta kalender via
   kopplingshändelse" med tomt fält. Kalendern ska bli vald automatiskt.
6. **Telefon A:** "Skriv testhändelse". Se hur snabbt den syns under "Senast ändrat" på
   telefon B.
7. **Valfritt, B på riktig telefon:** kör `BIND=0.0.0.0 server/start.sh` på Macen. Ändra
   adressen till `webcal://<macens-ip>:8787/feed.ics` och tryck Prenumerera.
   - Lägg till händelser med
     `curl -X POST <mac>:8787/events -d '{"title":"Test"}'`.
   - Notera när de dyker upp utan att Kalender-appen öppnas.

## Öppna frågor

- Hur ofta en riktig iPhone på batteri hämtar ett prenumererat flöde. Simulatorn hämtade
  det ungefär var 36:e minut.
- Om Family Sharing fortfarande skapar en delad "Familj"-kalender på iOS 26. I så fall är
  det noll delningssteg för par i samma familjegrupp, och kalendern hittas med samma
  kopplingshändelse.

## Filer

- `spike/` – SwiftUI-testapp (xcodegen):
  - `CalendarLab.swift` innehåller alla EventKit-experiment.
  - Appen kan styras från Macen med `xcrun simctl openurl <enhet> "kalenderspike://link"`
    (även `create`, `select?title=`, `find?key=`, `test`, `open?url=`, `reload`).
- `spike/server/` – testservrar:
  - `spike-server.mjs` (webcal-flöde, profil, `POST /events`). Den loggar varje hämtning
    av flödet, så att man ser när iOS uppdaterar.
  - Radicale som CalDAV-server.
  - `start.sh` startar båda.
