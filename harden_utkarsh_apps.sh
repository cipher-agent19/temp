#!/usr/bin/env bash
# Harden docs.utkarshraj.work + board.utkarshraj.work to only allow:
#   VPS1 public IP (68.168.222.151)
#   VPS2 public IP (162.35.173.192)
#   WireGuard mesh (10.7.0.0/24)
# Run as ROOT on VPS1. Idempotent - safe to re-run (backs up and skips already-hardened).
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

# Find each server block: collect its brace range. A server block = a '{' ... matching '}'
# at brace-depth 0 -> 1, scanning line by line.
def parse_blocks(lines):
    # returns list of (server_name, start_line_idx, end_line_idx, is_https)
    blocks = []
    i = 0
    n = len(lines)
    while i < n:
        s = lines[i].strip()
        if s == 'server' or s.startswith('server '):
            # find '{'
            j = i
            depth = 0
            start = None
            # scan forward until we see the opening brace, then count to closing
            k = i
            # find opening brace
            while k < n and '{' not in lines[k]:
                k += 1
            if k >= n:
                break
            # process brace from line k
            depth = 0
            body_start = k
            m = k
            # count braces from line k onward
            for m in range(k, n):
                depth += lines[m].count('{') - lines[m].count('}')
                if depth <= 0:
                    break
            # gather block text lines i..m
            blocktxt = '\n'.join(lines[i:m+1])
            server_name = None
            mm = re.search(r'server_name\s+([a-zA-Z0-9_.-]+);', blocktxt)
            if mm:
                server_name = mm.group(1)
            is_https = bool(re.search(r'listen\s+443\s+ssl', blocktxt))
            blocks.append({'name': server_name, 'text': blocktxt,
                           'start': i, 'end': m})
            i = m + 1
        else:
            i += 1
    return blocks

blocks = parse_blocks(lines)
out = lines[:]
# We'll rebuild the file by replacing the target blocks' text with appended ACL.
# Work bottom-up so indices stay valid... simpler: rebuild whole file from original lines,
# replacing ranges.
text = '\n'.join(lines)
targets = [b for b in blocks if b['name'] in ('docs.utkarshraj.work','board.utkarshraj.work') and b['is_https']]
applied = []
for b in targets:
    bt = b['text']
    if 'allow 68.168.222.151' in bt:
        applied.append(f"{b['name']}: already hardened (skip)")
        continue
    # insert ACL right after the opening of the server block body - after "server_name X;" line
    # Insert after the first "server_name ...;" within block, so ACL is at server context.
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
grep -nE 'allow |deny |server_name (docs|board)' "$CONF" | grep -E 'allow|deny|server_name (docs|board)' || true
