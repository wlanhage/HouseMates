#!/usr/bin/env bash
# ============================================================
# Planeraren – serverbootstrap för Oracle Cloud Free Tier
# (Ubuntu 22.04/24.04, ARM eller x86)
#
# Kör på en FÄRSK VM som root:
#   curl -fsSL https://raw.githubusercontent.com/wlanhage/HouseMates/main/deploy/setup-server.sh | sudo bash
# eller med egen domän:
#   curl -fsSL ... | sudo bash -s -- planeraren.example.com
#
# Gör allt: Node 22, Caddy (HTTPS), appbygge, .env med genererade
# nycklar, systemd-tjänst, brandvägg, nattlig databas-backup.
# Säker att köra igen (uppdaterar appen till senaste main).
# ============================================================
set -euo pipefail

REPO="https://github.com/wlanhage/HouseMates.git"
APP_DIR="/opt/planeraren"
APP_USER="planeraren"
PORT=3000

if [ "$(id -u)" -ne 0 ]; then
  echo "Kör som root: sudo bash setup-server.sh" >&2
  exit 1
fi

PUBLIC_IP=$(curl -fsS ifconfig.me || curl -fsS icanhazip.com)
DOMAIN="${1:-${PUBLIC_IP//./-}.sslip.io}"
echo "==> Domän: https://$DOMAIN (ip: $PUBLIC_IP)"

# ── Paket ────────────────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
echo "==> Installerar paket..."
apt-get update -qq
apt-get install -y -qq curl git build-essential python3 sqlite3 \
  debian-keyring debian-archive-keyring apt-transport-https iptables-persistent >/dev/null

if ! command -v node >/dev/null || [ "$(node -e 'console.log(process.versions.node.split(".")[0])')" -lt 20 ]; then
  echo "==> Installerar Node 22..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null
  apt-get install -y -qq nodejs >/dev/null
fi

if ! command -v caddy >/dev/null; then
  echo "==> Installerar Caddy..."
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq && apt-get install -y -qq caddy >/dev/null
fi

# ── Appanvändare + kod ───────────────────────────────────────
id -u "$APP_USER" >/dev/null 2>&1 || useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"

if [ -d "$APP_DIR/.git" ]; then
  echo "==> Uppdaterar appen..."
  git -C "$APP_DIR" fetch --quiet origin main
  git -C "$APP_DIR" reset --hard --quiet origin/main
else
  echo "==> Klonar appen..."
  git clone --quiet "$REPO" "$APP_DIR"
fi
mkdir -p "$APP_DIR/data" "$APP_DIR/data/backups"

echo "==> Bygger (npm ci + build)..."
cd "$APP_DIR"
npm ci --no-audit --no-fund --loglevel=error
npm run build >/dev/null

# ── .env (skapas EN gång – nycklar bevaras vid omkörning) ────
if [ ! -f "$APP_DIR/.env" ]; then
  echo "==> Genererar .env med nya nycklar..."
  ENC_KEY=$(openssl rand -base64 32)
  VAPID=$(node -e "const wp=require('$APP_DIR/node_modules/web-push');const k=wp.generateVAPIDKeys();console.log(k.publicKey+' '+k.privateKey)")
  VAPID_PUB=${VAPID%% *}
  VAPID_PRIV=${VAPID##* }
  cat > "$APP_DIR/.env" <<EOF
DATABASE_PATH=$APP_DIR/data/prod.db
APP_ENCRYPTION_KEY=$ENC_KEY
SESSION_TTL_DAYS=180
CALDAV_SERVER=https://caldav.icloud.com
CALDAV_CALENDAR_NAME=Gemensamt
VAPID_PUBLIC_KEY=$VAPID_PUB
VAPID_PRIVATE_KEY=$VAPID_PRIV
VAPID_SUBJECT=mailto:planeraren@$DOMAIN
PUBLIC_APP_NAME=Planeraren
TZ_DEFAULT=Europe/Stockholm
SYNC_INTERVAL_MINUTES=5
PORT=$PORT
ORIGIN=https://$DOMAIN
EOF
  chmod 600 "$APP_DIR/.env"
fi
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

# ── systemd-tjänst ───────────────────────────────────────────
echo "==> Skapar systemd-tjänst..."
cat > /etc/systemd/system/planeraren.service <<EOF
[Unit]
Description=Planeraren (parplanerings-PWA)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$APP_DIR
ExecStart=$(command -v node) --env-file=$APP_DIR/.env $APP_DIR/build/index.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now planeraren
systemctl restart planeraren

# ── Caddy (HTTPS med automatiska certifikat) ─────────────────
echo "==> Konfigurerar Caddy..."
cat > /etc/caddy/Caddyfile <<EOF
$DOMAIN {
	reverse_proxy 127.0.0.1:$PORT
	encode gzip
}
EOF
systemctl reload caddy || systemctl restart caddy

# ── Brandvägg (Oracle-images blockerar allt utom 22) ─────────
echo "==> Öppnar port 80/443 i iptables..."
iptables -C INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT 2>/dev/null \
  || iptables -I INPUT 1 -p tcp -m multiport --dports 80,443 -j ACCEPT
netfilter-persistent save >/dev/null

# ── Nattlig backup (04:30, behåller 14 dagar) ────────────────
cat > /etc/cron.d/planeraren-backup <<EOF
30 4 * * * $APP_USER sqlite3 $APP_DIR/data/prod.db ".backup $APP_DIR/data/backups/prod-\$(date +\%F).db" && find $APP_DIR/data/backups -name 'prod-*.db' -mtime +14 -delete
EOF

sleep 2
STATUS=$(systemctl is-active planeraren)
echo ""
echo "============================================================"
echo "  Klart! Tjänsten är: $STATUS"
echo "  URL: https://$DOMAIN"
echo ""
echo "  NÄSTA STEG – skapa era två användare:"
echo "    cd $APP_DIR && sudo -u $APP_USER node --env-file=.env \\"
echo "      deploy/create-users.mjs <id1> <Namn1> <lösen1> <id2> <Namn2> <lösen2>"
echo ""
echo "  OBS: Öppna även port 80+443 i Oracle-konsolen"
echo "  (VCN → Security List → Ingress Rules), annars når"
echo "  certifikatutfärdaren inte servern."
echo "============================================================"
