#!/usr/bin/env bash
# One-shot: HTTPS for docs/board/map.utkarshraj.work via certbot --nginx plugin.
# Requires the HTTP server blocks from cipher-vhosts.sh to exist (port 80).
# Safe: installs plugin, runs certbot --nginx, validates, rolls back certbot's
# changes if nginx -t fails. Run as root.
set -uo pipefail

[ "$(id -u)" -eq 0 ] || { echo "RUN AS ROOT"; exit 1; }

DOMAIN=utkarshraj.work
SITES="docs board map"
NOCONF=/etc/nginx/conf.d/cipher-utkarsh-apps.conf
TS=$(date +%Y%m%d_%H%M%S)

echo "== 0. Ensure HTTP server blocks exist (from cipher-vhosts.sh) =="
if [ ! -f "$NOCONF" ]; then
  echo "!! Missing $NOCONF (the HTTP vhosts). Re-add them first or re-run cipher-vhosts.sh."
  exit 1
fi
grep -q "docs.$DOMAIN" "$NOCONF" || { echo "!! docs.$DOMAIN not in $NOCONF"; exit 1; }
echo "   HTTP vhosts present."

echo "== 1. Install certbot nginx plugin =="
apt-get install -y python3-certbot-nginx certbot >/dev/null 2>&1 || { echo "plugin install failed"; exit 1; }
echo "   plugin ready."

echo "== 2. Backup nginx conf =="
cp "$NOCONF" "${NOCONF}.bak-precertbot.${TS}" && echo "   backup -> ${NOCONF}.bak-precertbot.${TS}"

echo "== 3. Run certbot --nginx (obtain certs + add 443 + redirect) =="
certbot --nginx --non-interactive --agree-tos \
  -m utkarsh@longstraw.in \
  --redirect \
  -d docs.$DOMAIN -d board.$DOMAIN -d map.$DOMAIN 2>&1 | tail -20
CBRC=$?
echo "   certbot rc=$CBRC"
if [ "$CBRC" -ne 0 ]; then
  echo "!! certbot failed. Restoring pre-certbot config (HTTP only)."
  cp "${NOCONF}.bak-precertbot.${TS}" "$NOCONF"
  nginx -t && (systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || nginx -s reload)
  exit 1
fi

echo "== 4. Validate + reload nginx =="
if ! nginx -t; then
  echo "!! nginx -t FAILED. Rolling back to pre-certbot config."
  cp "${NOCONF}.bak-precertbot.${TS}" "$NOCONF"
  nginx -t && (systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || nginx -s reload)
  exit 1
fi
(systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || nginx -s reload) && echo "nginx reloaded"

echo "== 5. Verify from localhost (--resolve to host) =="
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
for s in $SITES; do
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 --resolve "$s.$DOMAIN:443:127.0.0.1" "https://$s.$DOMAIN/" 2>/dev/null)
  echo "   https://$s.$DOMAIN -> HTTP $code"
done

echo ""
echo "DONE. Open on your phone:"
echo "  https://docs.utkarshraj.work (Docmost)"
echo "  https://board.utkarshraj.work (Vikunja)"
echo "  https://map.utkarshraj.work   (Mindmap)"
echo "Auto-renew: systemctl list-timers | grep certbot"
