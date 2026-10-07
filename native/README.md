# HouseMates native

MVP (2026-10-05): inloggning, hushåll för två, delad inköpslista i realtid, delad kalender via
iPhonens egen kalender (väg A nedan) och notiser till partnern. Sedan 2026-10-07 även att göra,
städ, Våra middagar, en Hem-flik, "för vem" på händelser och en månadsvy i kalendern. SwiftUI-app i `app/`, eget Supabase-projekt i `supabase/`. Webbappen och
dess databas påverkas inte.

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
   ändringen syns direkt i appen. `todo <uppgift>`, `chore <syssla>` och `done <titel>` gör
   samma sak för att göra och städ. `recipe <länk>` sparar ett recept i Våra middagar (kräver
   `supabase functions serve`, se nästa punkt). `partner.mjs leave` låter Anna lämna hushållet.
5. Se vilka notiser som skulle skickas (torrt, utan APNs-nyckel):
   ```bash
   (cd native && supabase functions serve --env-file supabase/functions/.env)
   ```
   `supabase/functions/.env` behöver raden `CRON_SECRET=lokal-hemlighet`. Kör sedan
   `node native/supabase/notify-check.mjs` i en annan terminal.
6. Mejl (till exempel "Glömt lösenordet") hamnar i den lokala brevlådan på
   http://127.0.0.1:55324. Länken i mejlet öppnas med
   `xcrun simctl openurl booted "<länken>"`.

Testerna:
- `node native/supabase/smoke.mjs`: behörigheter, triggers och notiskö mot den lokala databasen.
- `npm test`: bland annat APNs-signeringen (`tests/native-notify.test.ts`), och att
  notislogiken som kopierats från webbappen är identisk med originalet.
- Swift-testerna i `app/HouseMatesTests`: `xcodebuild test -project app/HouseMates.xcodeproj
  -scheme HouseMates -destination 'platform=iOS Simulator,name=<simulator>'`.

## Hur det hänger ihop

- **Inloggning:** e-post och lösenord (Supabase Auth). Namnet sparas i `profiles`.
  - Glömt lösenordet: mejlet innehåller en länk som öppnar appen (`housemates://nytt-losenord`),
    som frågar efter ett nytt lösenord. Länken fungerar bara på telefonen som bad om den,
    eftersom den bär en engångskod som appen sparat (PKCE).
  - Bekräftelselänken vid nytt konto loggar in i appen (`housemates://inloggad`).
  - Mejlen är på svenska (`supabase/templates`).
- **Hushåll:** den ena skapar, den andra går med med en sexteckenskod. Max två medlemmar.
  Alla tabeller bär `household_id`, och RLS släpper bara igenom det egna hushållet.
- **Listorna** (inköp, uppgifter, städ) synkas på samma sätt, av `SyncedTable`:
  - Ändringar visas direkt, sparas i en kö på telefonen och skickas i tur och ordning.
  - Utan nät ligger kön kvar, även om appen stängs, och skickas när kontakten är tillbaka.
    Appen försöker igen var tionde sekund. Samma sak när servern inte svarar (till exempel 503).
    Bara en ändring som databasen nekat med en felkod (dubblett, ogiltigt värde) släpps.
  - Listorna och hushållet sparas på telefonen, så appen visar senaste läge direkt, även utan nät.
  - Realtid hämtar om en lista när partnern ändrar något. Listorna hämtas också om när appen
    kommer tillbaka från bakgrunden, ifall realtidsanslutningen brutits.
  - Varje tabell beskriver bara sina ändringar (`ShoppingChange`, `TodoChange`, `ChoreChange`):
    hur de syns i listan och hur de skickas.
- **Inköp:** `shopping_items`. Samma vara kan bara stå en gång (unikt index).
- **Att göra:** `todos` för engångsuppgifter och `chores` för återkommande städsysslor.
  - En uppgift kan ha sista dag och en period ("kan göras från"). Datumen är rena dagar i
    telefonens tidszon (`LocalDay`), aldrig midnatt i UTC.
  - En städsyssla har ett intervall. Nästa gång räknas från när den senast gjordes, samma regel
    som webbappen. Servern sätter vem som gjorde den och godtar inga datum i framtiden.
  - Klara uppgifter raderas efter 30 dagar (`cron.sql`).
- **Våra middagar:** `favorites`, öppnas från Inköp. Ingredienserna sparas som råa rader
  ("500 g köttfärs") och delas i vara och mängd (`Ingredient`, samma regler som webbappens
  `ingredients.ts`) först när de läggs på listan, som "Köttfärs · 500 g" (`shopping_items.qty`).
  - Allt utom det som redan står på listan är förvalt. Ett tryck lägger varorna på listan.
  - Import från en länk: edge function `recipe-import` hämtar sidan och läser schema.org/Recipe
    med webbappens tolkning (`_shared/recipe.ts`, kopia med identitetstest). Bara medlemmar i
    ett hushåll kan använda den. Den hämtar bara publika sajter: varje adress, också efter en
    omdirigering, slås upp och nekas om den pekar på det egna nätet. Högst 2 MB läses.
  - Dela från Safari: delningstillägget (`app/HouseMatesShare`) lägger länken i en inkorg i en
    App Group (`group.se.housemates.app`). Appen hämtar receptet nästa gång den öppnas.
    Tillägget har ingen inloggning. En sida som inte går att läsa sparas ändå, med sajtens namn,
    så att länken inte försvinner.
- **Färger:** den som skapar hushållet blir blå och den som går med rosa. Gemensamt är grönt,
  som i webbappen. Färgen visas vid uppgifter och sysslor.
- **Kalender:** finns bara i telefonerna (EventKit). Den som sätter upp väljer en delad
  kalender eller skapar en ny. Kalenderns titel och UID för några händelser sparas i
  `households`, så partnerns app hittar samma kalender själv. Händelser skapas och ändras i
  Apples egen redigeringsvy.
  - Har man nekat kalenderåtkomst frågar iOS inte igen. Kalenderfliken visar då "Öppna
    Inställningar".
  - Har kalendern raderats eller slutat delas kan vem som helst av er välja en ny kalender
    för hushållet från vänteläget. Partnerns telefon följer med automatiskt.
  - **För vem:** efter en ny händelse frågar appen vem den är för. Svaret sparas i
    `event_assignees` med händelsens UID (händelsen själv finns bara i telefonerna), och pricken
    får personens färg på båda telefonerna. Håll inne på en händelse för att ändra.
  - Lista eller månad: månadsvyn visar en prick per händelse i personens färg och den valda
    dagens händelser under rutnätet (`MonthGrid`, samma regler som webbappens `monthGrid.ts`).
- **Hem:** dagens händelser, uppgifter med sista dag idag eller tidigare, städsysslor som ska
  göras, och "Nyligen i inköp" ur `activity_log`. Samma person och slag inom 30 minuter blir en
  rad, som i webbappens `activityFeed.ts`. Flödet hämtas om när inköpslistan ändras.
- **Notiser:** varje ändring skriver en rad i `activity_log` i samma transaktion (trigger). För
  kalendern rapporterar appen sina ändringar via `log_calendar_activity`. Raden köas till
  partnern. Edge function `notify` körs varje minut (`supabase/cron.sql`) och skickar EN samlad
  notis när det varit tyst i tre minuter. Det är samma digest som webbappen. Ett tryck på
  notisen öppnar rätt flik.
  - Tysta timmar per person (`notification_prefs`, med telefonens tidszon). Notiser under
    natten skjuts upp till när de tysta timmarna slutar, med samma testade logik som webbappen.
- **Lämna hushåll:** `leave_household()` tar bort medlemskapet och de notiser som väntar
  till den som lämnar.
  - Den som är sist kvar tar hushållet och listan med sig.
  - Annars blir listan kvar för partnern, och inbjudningskoden byts så att den som lämnade
    inte kan gå med igen med den gamla.
- **Radera konto:** `delete_account()` lämnar först hushållet och tar sedan bort
  inloggningen. Profil, push-token, egen historik och återstående notiser följer med
  (`on delete cascade`).
  - Varor, uppgifter och sysslor man lagt till blir kvar för partnern, utan koppling till
    personen.
  - Appen rensar sedan allt den sparat på telefonen.
  - Kalendern i Apple Kalender rörs inte. Den ligger i iCloud och kan vara delad med partnern.

## Verifierat i simulatorn (2026-10-05–07)

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
- lämna hushållet med partner kvar: listan blir kvar för partnern och koden byts. Den
  gamla koden nekas i "Gå med", den nya fungerar.
- radera konto, både ensam i hushållet (hushåll och lista raderas) och med partner (listan
  blir kvar för partnern, utan koppling till personen), och innan man har ett hushåll
- push: bannern visas med rätt svensk text (simulerad leverans med `simctl push`)
- utan kontakt med servern: lägga till och bocka av fungerar, en rad säger att ändringarna
  skickas senare, och kön ligger kvar när appen startas om. När servern var tillbaka nådde
  ändringarna databasen inom 7 sekunder.
- appen visar listan och hushållet från telefonen direkt vid start
- partnerns ändring medan appen låg i bakgrunden syns när appen öppnas igen
- nekad kalenderåtkomst ger "Öppna Inställningar"; vänteläget kan byta kalender för hushållet
- glömt lösenord hela vägen:
  1. mejlet (på svenska) med länk
  2. Safari frågar "Öppna i HouseMates?"
  3. appen visar "Nytt lösenord"
  4. det gamla lösenordet nekas och det nya fungerar
- tysta timmar sparas från appen, och notis-workern sköt upp en notis till exakt när de tar slut
- integritetspolicyn visas i appen under Inställningar → Om HouseMates
- att göra: ny uppgift med person och sista dag, bocka av och ångra. Partnerns uppgift syns
  direkt. Utan kontakt med servern köas en ny uppgift och når databasen när servern är tillbaka.
- städ: partnern bockar av och raden visar "Gjord idag av Anna · Om 7 dagar". Ändrat intervall
  och ångrad avbockning sparas, och ångra ger ingen notis.
- notistexten för uppgifter och städ ("William klarade av Byt glodlampa") leder till fliken
  Att göra
- middagar: ett recept från ICA hämtas via länk med namn, bild och 17 ingredienser. Ett tryck
  lägger de valda varorna på listan med mängd ("Cream cheese · 150 g"), och arket stängs.
- dela från Safari: HouseMates finns i delningsmenyn. Tillägget sparar länken, och appen hämtar
  receptet (13 ingredienser) när den öppnas. Inkorgen töms efteråt.
- en länk som bara öppnar appen (`housemates://`) ger inget felmeddelande
- för vem: efter en ny händelse kommer frågan "För vem är …?". Valet sparas och pricken får
  personens färg. Långtryck byter person.
- månadsvyn: rätt veckodagar och prickar, val av dag visar dagens händelser, byte av månad
- Hem: dagens händelse i personens färg, uppgift med sista dag idag, och inköpsflödet
  grupperat per person ("William la till 8 varor")

**Inte verifierat:**
- att ett tryck på notisen öppnar rätt flik (simulatorns notiscenter tog inte emot tryck
  från testverktyget)
- att "Öppna Inställningar" landar på appens egen sida. I simulatorn öppnades
  Inställningars startsida, troligen eftersom appens behörighet just hade tagits bort med
  `simctl`.
- riktig APNs-leverans (kräver nyckel)
- två fysiska telefoner med iCloud-delning

## Kvar före TestFlight och App Store

1. **Betalt Apple Developer-konto.**
   - Slå på Push Notifications för `se.housemates.app` och ladda ner en APNs-nyckel (.p8).
   - Sätt secrets på det hostade projektet: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`
     (innehållet i .p8-filen), `APNS_BUNDLE_ID=se.housemates.app` och `CRON_SECRET`.
     Lägg till `APNS_PRODUCTION=true` för TestFlight och App Store.
   - Lägg till `aps-environment` i appens entitlements.
   - Registrera App Group `group.se.housemates.app` och slå på den för både
     `se.housemates.app` och `se.housemates.app.share` (delningstillägget). Ett gratiskonto kan
     inte signera App Groups.
2. **Hostat Supabase-projekt, i EU** (policyn lovar servrar inom EU).
   - Kör `supabase link` och `supabase db push`, deploya `notify` och `recipe-import`, och kör
     `cron.sql`.
   - Kör `supabase config push`. Det för över länkadresserna (`additional_redirect_urls`) och
     de svenska mejlmallarna.
   - Koppla en egen e-posttjänst (SMTP). Supabases inbyggda klarar bara ett par mejl i timmen.
   - Lägg till en `Config/Release.xcconfig` med projektets adress och nyckel, och
     `SUPPORT_EMAIL`.
3. **Fyll i och publicera integritetspolicyn.**
   - Byt `[NAMN]` och `[E-POST]` i `app/HouseMates/integritetspolicy.md`.
   - Publicera samma text på en webbadress. Den adressen och en support-adress behövs i App
     Store Connect.
4. **App Store Connect:** texter, granskningsanteckningar och integritetssvar finns i
   `appstore/README.md`.
   - Skapa två demokonton i samma hushåll åt granskarna.
   - Ta skärmbilder för 6,9 tum.
5. **Riktig app-ikon.** Den nuvarande är tillfällig: ett vitt hus på grönt.
6. **Versionsnummer:** räkna upp `CURRENT_PROJECT_VERSION` i `project.yml` inför varje
   uppladdning. App Store Connect nekar samma byggnummer två gånger.
7. **Senare:** flytta in er befintliga data från webbappen.

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
