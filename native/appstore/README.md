# App Store Connect: texter och svar

Klistras in i App Store Connect vid första uppladdningen. Hakparenteser är sådant som måste
fyllas i först.

## Appinformation

- **Namn:** HouseMates
- **Underrubrik (max 30 tecken):** Inköp och kalender för två
- **Primär kategori:** Produktivitet
- **Sekundär kategori:** Livsstil
- **Åldersgräns:** 4+ (inget olämpligt innehåll, ingen chatt, inga köp)
- **Copyright:** 2026 [NAMN]
- **Support-URL:** [adress till en sida med kontaktuppgifter]
- **Integritetspolicy-URL:** [adress där `app/HouseMates/integritetspolicy.md` publiceras]; den
  engelska listan får länka till `app/HouseMates/privacy-policy.md`
- **Namnet:** App Store-namn är unika. Skapa appen i App Store Connect tidigt; är "HouseMates"
  upptaget måste namnet få ett tillägg, till exempel "HouseMates – för två".
- **EU (Digital Services Act):** ange trader-status under Business i App Store Connect. Utan
  status visas appen inte i EU. Som privatperson utan försäljning: inte trader; som trader visas
  adress, telefon och e-post i App Store.
- **Innehållsrättigheter:** appen visar tredjepartsinnehåll (receptbilder och länkar som
  användaren importerar) och länkar alltid till källan.

## Kampanjtext (max 170 tecken)

Inköpslistan, kalendern, städet och middagarna ni delar – på båda era telefoner, med en notis
när den andra har handlat eller lagt in något nytt.

## Beskrivning

HouseMates är appen för er två som delar hem.

INKÖPSLISTA SOM FUNGERAR I BUTIKEN
Lägg till varor, bocka av när ni handlar och se direkt vad den andra har lagt till. Har ni
dålig täckning i butiken fungerar listan ändå; ändringarna skickas när nätet är tillbaka.

ER GEMENSAMMA KALENDER
HouseMates använder kalendern ni redan har i telefonen. Välj en kalender ni delar, eller
skapa en ny och dela den med din partner. Händelserna syns i både HouseMates och Kalender-appen,
och ni ser vem varje händelse gäller.

ATT GÖRA OCH STÄD
Uppgifter med datum och vem som ska göra dem. Städsysslor som kommer tillbaka med jämna
mellanrum, så att ni ser vad som var längesedan.

MIDDAGAR
Spara era favoritmiddagar med ingredienser och lägg allt på inköpslistan med ett tryck.
Hämta recept direkt från en länk.

NOTISER SOM INTE STÖR
Få en samlad notis när din partner har handlat eller lagt in något, i stället för en per
vara. Med tysta timmar väntar notiserna tills du har vaknat.

INGA ANNONSER, INGEN SPÅRNING
Det ni lägger in används bara för att appen ska fungera. Kalenderns händelser stannar i
din egen kalender.

## Nyckelord (max 100 tecken, kommaseparerade)

inköpslista,sambo,par,delad kalender,att göra,städschema,hushåll,handla,middag,recept

## På engelska

Appen finns på svenska och engelska, så App Store-sidan bör också finnas på engelska (lägg till
English (U.K.) eller English (U.S.) under Localizations).

- **Underrubrik (max 30 tecken):** Shopping & calendar for two
- **Kampanjtext:** The shopping list, calendar, chores and dinners you share – on both your
  phones, with a notification when the other one has shopped or added something new.
- **Nyckelord:** shopping list,couple,shared calendar,to do,chores,household,groceries,dinner,recipes
- **Beskrivning:**

```
HouseMates is the app for the two of you who share a home.

A SHOPPING LIST THAT WORKS IN THE SHOP
Add items, tick them off while you shop and see straight away what the other one has added.
If coverage in the shop is poor, the list still works; your changes are sent when you're
back online.

YOUR SHARED CALENDAR
HouseMates uses the calendar you already have on your phone. Choose a calendar you share, or
create a new one and share it with your partner. Events show up both in HouseMates and in the
Calendar app, and you can see who each event is for.

TO-DOS AND CHORES
Tasks with dates and who should do them. Chores that come back at regular intervals, so you
can see what was done a long time ago.

DINNERS
Save your favourite dinners with ingredients and put everything on the shopping list with one
tap. Fetch recipes straight from a link.

NOTIFICATIONS THAT DON'T DISTURB
Get one combined notification when your partner has shopped or added something, instead of
one per item. With quiet hours, notifications wait until you're awake.

NO ADS, NO TRACKING
What you add is only used to make the app work. Your calendar events stay in your own
calendar.
```

## Granskningsanteckningar (till Apples granskare, på engelska)

```
HouseMates is a planner for two people who share a home: shopping list, to-dos, chores,
dinner recipes and a shared calendar. The app is in English and Swedish; it follows the
device language, and Settings -> Language changes it.

Demo accounts (already in the same household, with sample data):
  [e-post 1] / [lösenord 1]
  [e-post 2] / [lösenord 2]

Navigation: the tab bar has Home, Calendar, Shopping and To do. The green + in the middle
adds an event, an item, a task or a chore. Settings is the gear icon at the top right.

Calendar access: the app shows and edits the ONE calendar the couple chooses to share
(Calendar tab). iOS has no permission for a single calendar, so the app asks for full
access; it never reads other calendars' events and never uploads calendar content. When
the user creates an event in the app, only its title and start time are sent to our server
so the partner can get a notification. To test on one device: Calendar tab -> Continue ->
allow access -> "Create a new HouseMates calendar" -> + -> New event.

Recipes: share a recipe page from Safari to HouseMates with the share sheet. It appears
under Shopping -> Dinners the next time the app opens.

Push notifications: sent to the partner when something changes, collected into one
notification after a few quiet minutes (Settings -> Notifications). To see one, sign in
with the second demo account on another device and add an item.

Account deletion: Settings (gear icon) -> Delete account.
```

## Integritetsuppgifter (App Privacy)

Svaren ska stämma med `app/HouseMates/PrivacyInfo.xcprivacy`.

- **Spårning:** Nej.
- **Data som samlas in.** Alla är kopplade till användaren och används bara för appens
  funktion (App Functionality):
  - Kontaktuppgifter → E-postadress
  - Kontaktuppgifter → Namn
  - Identifierare → Användar-id
  - Identifierare → Enhets-id (Device ID; telefonens adress för pushnotiser)
  - Användarinnehåll → Övrigt användarinnehåll (inköpslista, uppgifter, städsysslor, middagar,
    titel och tid för händelser som skapas i appen, och vem en händelse är för)
- **Inte insamlat:** plats, kontakter, hälsa, ekonomi, webbhistorik, sökhistorik, diagnostik,
  användningsdata och köp.

## Exportregler

Appen använder bara HTTPS från iOS. `ITSAppUsesNonExemptEncryption` är satt till `NO`, så
frågan besvaras automatiskt vid varje uppladdning.

## Skärmbilder

Det krävs bilder för 6,9 tum (iPhone 17 Pro Max, 1320 × 2868). Ta dem i simulatorn med
demohushållet: Hem, Kalender (månad), Inköp, Att göra och Våra middagar, en uppsättning på
svenska och en på engelska (Inställningar → Språk).
