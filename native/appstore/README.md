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
- **Integritetspolicy-URL:** [adress där `app/HouseMates/integritetspolicy.md` publiceras]

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

## Granskningsanteckningar (till Apples granskare, på engelska)

```
HouseMates is a planner for two people who share a home: shopping list, to-dos, chores,
dinner recipes and a shared calendar.

Demo accounts (already in the same household, with sample data):
  [e-post 1] / [lösenord 1]
  [e-post 2] / [lösenord 2]

Calendar access: the app shows and edits the ONE calendar the couple chooses to share
(Calendar tab). iOS has no permission for a single calendar, so the app asks for full
access; it never reads other calendars' events and never uploads calendar content. When
the user creates an event in the app, only its title and start time are sent to our server
so the partner can get a notification. To test on one device: Calendar tab -> Continue ->
allow access -> "Skapa ny HouseMates-kalender" -> + to add an event.

Push notifications: sent to the partner when something changes, collected into one
notification after three quiet minutes.

Account deletion: Settings (Inställningar) -> Radera konto.
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
demohushållet, en per flik.
