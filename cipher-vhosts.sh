#!/usr/bin/env bash
# One-shot: wire docs/board/map.utkarshraj.work on the EXISTING host nginx
# (the one owning 80/443) -> cipher's podman apps on 127.0.0.1.
# Safe: backs up config, validates, auto-rolls-back on failure, verifies.
set -uo pipefail

[ "$(id -u)" -eq 0 ] || { echo "RUN AS ROOT"; exit 1; }

DOMAIN=utkarshraj.work
NCONF=/etc/nginx/conf.d/cipher-utkarsh-apps.conf
TS=$(date +%Y%m%d_%H%M%S)

echo "== backing up existing config (if any) =="
[ -f "$NCONF" ] && cp "$NCONF" "${NCONF}.bak.${TS}" && echo "backup -> ${NCONF}.bak.${TS}"

echo "== writing vhosts =="
cat > "$NCONF" <<'EOF'
# Cipher utkarshraj.work apps -> podman rootless (auto-generated)
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name docs.utkarshraj.work;
    client_max_body_size 100m;
    location / {
        proxy_pass http://127.0.0.1:8082;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
    }
}

server {
    listen 80;
    server_name board.utkarshraj.work;
    client_max_body_size 100m;
    location / {
        proxy_pass http://127.0.0.1:3456;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
    }
}

server {
    listen 80;
    server_name map.utkarshraj.work;
    client_max_body_size 100m;
    location / {
        proxy_pass http://127.0.0.1:8083;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
    }
}
EOF

echo "== validating nginx config =="
if ! nginx -t; then
    echo "!! CONFIG INVALID. Restoring backup."
    [ -f "${NCONF}.bak.${TS}" ] && cp "${NCONF}.bak.${TS}" "$NCONF"
    nginx -t
    exit 1
fi

echo "== reloading nginx =="
(systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || nginx -s reload) && echo "nginx reloaded"

echo "== verifying each subdomain (via localhost) =="
for s in docs board map; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: $s.$DOMAIN" "http://127.0.0.1/$s" 2>/dev/null)
    echo "  $s.$DOMAIN -> HTTP $code"
done

echo ""
echo "DONE. Try on your phone:"
echo "  http://docs.$DOMAIN   (Docmost)"
echo "  http://board.$DOMAIN  (Vikunja)"
echo "  http://map.$DOMAIN    (Mindmap)"
echo "NOTE: HTTP for now. Say the word if you want HTTPS (I'll add certbot)."
