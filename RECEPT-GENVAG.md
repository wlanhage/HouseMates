# Spara recept från Safari till HouseMates

En iPhone-genväg som dyker upp under **Dela** i Safari och sparar receptet som
favorit i HouseMates, utan att appen behöver öppnas. Byggs en gång per telefon
(ca 3 minuter). Fungerar på alla receptsajter som har receptdata inbäddad
(ICA, Köket, Arla, Tasteline, Zeta, Coop med flera).

## Innan du börjar

Öppna HouseMates → **Inställningar → Recept från Safari**:

1. Tryck **Skapa nyckel** (första gången).
2. Du behöver två saker därifrån: **Adressen** och **Din nyckel**. Båda har en
   Kopiera-knapp.

## Bygg genvägen

Öppna appen **Genvägar** → fliken Genvägar → **+** uppe till höger.

1. **Döp genvägen** till `Spara till HouseMates` (tryck på namnet högst upp).
2. Tryck på **i**-ikonen längst ner → slå på **Visa i delningsblad**.
   Under *Typer av delning* avmarkera allt utom **URL:er** och **Safari-webbsidor**.
3. Lägg till åtgärd **Hämta URL:er från indata** (sök på "URL:er").
   Indata ska vara **Indata från delningsblad** (sätts automatiskt).
4. Lägg till åtgärd **Hämta innehållet från URL** (sök på "innehåll"). Ställ in:
   - **URL**: klistra in *Adressen* från Inställningar
     (slutar på `/functions/v1/recipe-import`).
   - Fäll ut pilen under adressen:
     - **Metod**: `POST`
     - **Sidhuvuden** → lägg till ett: nyckel `x-import-token`, värde = *Din nyckel*.
     - **Text i begäran**: `JSON`. Lägg till **ett** fält:
       - vänstra rutan (nyckel): skriv ordet `url` med små bokstäver
       - högra rutan (värde): välj variabeln **URL:er** från steg 3
       (skriv inte in adressen här, det är receptlänken som ska skickas)
5. Lägg till åtgärd **Visa notis** (sök på "notis"). Som text väljer du
   variabeln **Innehållet från URL** från steg 4. Svaret är ren text, så inget
   mer behövs.
6. Tryck **Klar**.

## Testa

Öppna ett recept i Safari → **Dela** → **Spara till HouseMates**. Efter någon
sekund kommer en notis: *Sparad: Kycklinggryta (12 varor)*. Receptet ligger nu
under Inköp → bestick-ikonen → Våra middagar, med bild, ingredienser och länk
till originalet. Tryck på **+** vid en ingrediens eller **Lägg allt på listan**.

## Om något strular

| Notisen säger | Gör så här |
|---|---|
| *Fel nyckel* | Kopiera nyckeln från Inställningar igen och klistra in i steg 4. Har du tryckt **Byt nyckel** måste genvägen uppdateras. |
| *Kunde inte hämta sidan* | Sajten blockerar hämtning eller kräver inloggning. Klistra in länken manuellt under Våra middagar → + Ny, eller skriv in varorna. |
| *Inga ingredienser hittades* | Sajten saknar receptdata. Receptet är sparat med titel och länk, fyll i varorna i appen. |
| Ingen notis alls | Kontrollera att *Visa i delningsblad* är på och att adressen i steg 4 är komplett. |

Nyckeln ger bara rätt att spara favoriter i ert hushåll. Byt den under
Inställningar om den skulle hamna på villovägar.
