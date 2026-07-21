# Deploy: Oracle Cloud Free Tier (gratis för alltid)

Appen kräver en långlivad Node-process + beständig disk (SQLite, synkjobb,
SSE, push). Oracle Cloud Free Tier ger en alltid-på ARM-server gratis.

**OBS: använd ett privat Oracle-konto** – inget jobbrelaterat.

## 1. Skapa konto + VM (~10 min, engångs)

1. Skapa konto på <https://www.oracle.com/cloud/free/> (kort krävs för
   verifiering – inget dras; välj gärna region **Sweden Central (Stockholm)**
   eller Frankfurt).
2. Skapa instans: **Compute → Instances → Create instance**
   - Image: **Ubuntu 24.04** (aarch64)
   - Shape: **Ampere A1.Flex** – t.ex. 2 OCPU / 12 GB (inom Always Free)
   - Ladda ner/ange din SSH-nyckel
3. Öppna portar: **Networking → VCN → Security Lists → Default →
   Add Ingress Rules**: källa `0.0.0.0/0`, TCP, portar **80** och **443**.

## 2. Installera allt (ett kommando)

SSH:a in och kör:

```bash
ssh ubuntu@<serverns-ip>
curl -fsSL https://raw.githubusercontent.com/wlanhage/HouseMates/main/deploy/setup-server.sh | sudo bash
```

Scriptet installerar Node + Caddy (automatisk HTTPS), bygger appen,
genererar nycklar (`.env`), startar systemd-tjänsten, öppnar brandväggen
och lägger nattlig databas-backup. Utan argument används en gratis
`<ip>.sslip.io`-adress; har du egen domän (A-pekare mot serverns IP):

```bash
curl -fsSL .../setup-server.sh | sudo bash -s -- planeraren.dindomän.se
```

## 3. Skapa era användare

```bash
cd /opt/planeraren
sudo -u planeraren node --env-file=.env deploy/create-users.mjs \
  william William <lösenord1> partner <Namn2> <lösenord2>
```

## 4. Börja använd

- Öppna `https://<domänen>` på mobilen → logga in →
  **Dela → Lägg till på hemskärmen** (krävs för push på iOS).
- Inställningar → koppla er delade iCloud-kalender **"Gemensamt"**
  (Apple-ID + app-specifikt lösenord från account.apple.com).
- Inställningar → *Tillåt push på den här enheten*.

## Drift

| Vad | Hur |
|---|---|
| Uppdatera appen | Kör om setup-scriptet (nycklar/databas bevaras) |
| Loggar | `journalctl -u planeraren -f` |
| Status/omstart | `systemctl status/restart planeraren` |
| Backuper | `/opt/planeraren/data/backups/` (nattligen 04:30, 14 dagar) |
| Databas | `/opt/planeraren/data/prod.db` |

**sslip.io-notis:** certifikatutfärdning på delade sslip.io-domäner kan i
sällsynta fall stoppas av Let's Encrypts kvoter. Händer det: skaffa en
billig domän (eller gratis via DuckDNS) och kör om scriptet med den.
