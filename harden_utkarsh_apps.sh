#!/usr/bin/env bash
# Harden docs.utkarshraj.work + board.utkarshraj.work to only allow:
#   VPS1 public IP (68.168.222.151)
#   VPS2 public IP (162.35.173.192)
#   WireGuard mesh (10.7.0.0/24)
# Run as ROOT on VPS1. Idempotent - safe to re-run (backs up and skips already-hardened).
# FIXED: parser now stores is_https (was KeyError).
set -euo pipefail

CONF=/etc/nginx/conf.d/cipher-utkarsh-apps.conf
TS=$(date +%Y%m%d_%H%M%S)
cp "$CONF" "${CONF}.bak.lockdown.$TS"
echo "backup: ${CONF}.bak.lockdown.$TS"

python3 - "$CONF" <<'PY'
import sys, re
path = sys.argv[1]
lines = open(path).read().split('\n')

ALLOW_BLOCK = [
    '    allow 68.168.222.151;   # VPS1 public',
    '    allow 162.35.173.192;   # VPS2 / Hermes box public',
    '    allow 10.7.0.0/24;      # WireGuard mesh',
    '    deny all;',
]

def parse_blocks(lines):
    blocks = []
    i = 0
    n = len(lines)
    while i < n:
        s = lines[i].strip()
        if s == 'server' or s.startswith('server '):
            k = i
            while k < n and '{' not in lines[k]:
                k += 1
            if k >= n:
                break
            depth = 0
            m = k
            for m in range(k, n):
                depth += lines[m].count('{') - lines[m].count('}')
                if depth <= 0:
                    break
            blocktxt = '\n'.join(lines[i:m+1])
            server_name = None
            mm = re.search(r'server_name\s+([a-zA-Z0-9_.-]+);', blocktxt)
            if mm:
                server_name = mm.group(1)
            is_https = bool(re.search(r'listen\s+443\s+ssl', blocktxt))
            blocks.append({'name': server_name, 'text': blocktxt, 'is_https': is_https})
            i = m + 1
        else:
            i += 1
    return blocks

blocks = parse_blocks(lines)
text = '\n'.join(lines)
targets = [b for b in blocks if b['name'] in ('docs.utkarshraj.work','board.utkarshraj.work') and b['is_https']]
if not targets:
    print("WARN: no HTTPS server blocks found for docs/board; nothing changed")
    sys.exit(0)
applied = []
for b in targets:
    bt = b['text']
    if 'allow 68.168.222.151' in bt:
        applied.append(f"{b['name']}: already hardened (skip)")
        continue
    inserted = re.sub(r'(server_name\s+[a-zA-Z0-9_.-]+;\n)', r'\1' + '\n'.join(ALLOW_BLOCK) + '\n', bt, count=1)
    text = text.replace(bt, inserted, 1)
    applied.append(f"{b['name']}: ACL inserted")
open(path,'w').write(text)
for a in applied:
    print(a)
PY

echo "=== nginx -t ==="
nginx -t
echo "=== reload ==="
systemctl reload nginx && echo "reloaded OK"
echo "=== verify ==="
grep -nE 'allow |deny ' "$CONF"
# cache-bust 1788071103
