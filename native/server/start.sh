#!/bin/sh
# Starts Radicale (stand-in for "our own CalDAV server") and the spike server.
# BIND=0.0.0.0 ./start.sh makes both reachable from a real iPhone on the same Wi-Fi.
set -e
cd "$(dirname "$0")"
BIND="${BIND:-127.0.0.1}"
DATA="${DATA:-.radicale-data}"
mkdir -p "$DATA"
echo "hushall:spike-losen" > "$DATA/users"

if [ "$BIND" = "127.0.0.1" ]; then HOSTS="127.0.0.1:5232, [::1]:5232"; else HOSTS="$BIND:5232"; fi

python3 -m radicale \
  --server-hosts "$HOSTS" \
  --auth-type htpasswd \
  --auth-htpasswd-filename "$DATA/users" \
  --auth-htpasswd-encryption plain \
  --storage-filesystem-folder "$DATA/collections" \
  --logging-level info &
RADICALE_PID=$!
trap 'kill $RADICALE_PID' EXIT

sleep 1
curl -s -o /dev/null -u hushall:spike-losen -X MKCALENDAR "http://127.0.0.1:5232/hushall/housemates/" \
  -H 'Content-Type: application/xml' \
  --data '<?xml version="1.0"?><C:mkcalendar xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav"><D:set><D:prop><D:displayname>HouseMates</D:displayname></D:prop></D:set></C:mkcalendar>' || true

BIND="$BIND" node spike-server.mjs
