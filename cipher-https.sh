#!/usr/bin/env bash
# One-shot: get Let's Encrypt certs for docs/board/map.utkarshraj.work and
# add HTTPS (443) server blocks on the existing host nginx -> cipher apps.
# Idempotent-ish + safe (backup, validate, rollback). Run as root.
set -uo pipefail

[ "$(id -u)" -eq 0 ] || { echo "RUN AS ROOT"; exit 1; }

DOMAIN=utkarshraj.work
SITES="docs board map"
DIR=/var/www/letsencrypt
NCONF_FILES=""

echo "== ensure webroot + install certbot =="
mkdir -p "$DIR"
apt-get install -y certbot >/dev/null 2>&1 || { echo "certbot install failed"; exit 1; }

echo "== get certs (webroot challenge via existing :80 vhosts) =="
DOMAIN_ARGS=
for s in $SITES; do DOMAIN_ARGS="$DOMAIN_ARGS -d $s.$DOMAIN"; done
certbot certonly --webroot -w "$DIR" --agree-tos --non-interactive \
  -m utkarsh@longstraw.in --keep-until-expiring $DOMAIN_ARGS 2>&1 | tail -5
echo "certbot rc=$?"

echo "== write HTTPS vhosts =="
NCONF=/etc/nginx/conf.d/cipher-utkarsh-apps.conf
TS=$(date +%Y%m%d_%H%M%S)
[ -f "$NCONF" ] && cp "$NCONF" "${NCONF}.bak.${TS}" && echo "backup -> ${NCONF}.bak.${TS}"

cat > "$NCONF" <<EOF
# Cipher utkarshraj.work apps - HTTPS (auto-generated)
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

# --- HTTP: redirect to HTTPS + ACME webroot ---
server {
    listen 80;
    server_name docs.${DOMAIN} board.${DOMAIN} map.${DOMAIN};
    location /.well-known/acme-challenge/ { root $DIR; }
    location / { return 301 https://\$host\$request_uri; }
}

# --- docs (Docmost) ---
server {
    listen 443 ssl;
    server_name docs.${DOMAIN};
    ssl_certificate     /etc/letsencrypt/live/docs.${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/docs.${DOMAIN}/privkey.pem;
    client_max_body_size 100m;
    location / {
        proxy_pass http://127.0.0.1:8082;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
    }
}

# --- board (Vikunja) ---
server {
    listen 443 ssl;
    server_name board.${DOMAIN};
    ssl_certificate     /etc/letsencrypt/live/board.${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/board.${DOMAIN}/privkey.pem;
    client_max_body_size 100m;
    location / {
        proxy_pass http://127.0.0.1:3456;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
    }
}

# --- map (Mindmap) ---
server {
    listen 443 ssl;
    server_name map.${DOMAIN};
    ssl_certificate     /etc/letsencrypt/live/map.${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/map.${DOMAIN}/privkey.pem;
    client_max_body_size 100m;
    location / {
        proxy_pass http://127.0.0.1:8083;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
    }
}
EOF

echo "== validate + reload =="
if ! nginx -t; then
    echo "!! INVALID - restoring backup and exiting"
    [ -f "${NCONF}.bak.${TS}" ] && cp "${NCONF}.bak.${TS}" "$NCONF"
    nginx -t
    exit 1
fi
(systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || nginx -s reload) && echo "nginx reloaded"

echo "== verify HTTPS on localhost =="
for s in $SITES; do
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 --resolve "$s.$DOMAIN:443:127.0.0.1" "https://$s.$DOMAIN/" 2>/dev/null)
  echo "  https://$s.$DOMAIN -> HTTP $code (with --resolve, so may differ from public)"
done

echo ""
echo "DONE. On your phone open:"
echo "  https://docs.utkarshraj.work (Docmost)"
echo "  https://board.utkarshraj.work (Vikunja)"
echo "  https://map.utkarshraj.work   (Mindmap)"
echo "Auto-renew handled by certbot timer; run: systemctl list-timers | grep certbot"
