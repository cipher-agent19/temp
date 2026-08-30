#!/bin/sh
# install_kalinga_notes.sh - run as ROOT on VPS1.
# Three-way vault access: flatnotes (66536) owns, Cipher + root full access,
# default ACLs so every future file inherits the same access.
set -e

echo "[1/4] restore flatnotes ownership on the vault"
chown -R 66536:66536 /root/docs

echo "[2/4] grant Cipher (1001) + flatnotes (66536) ACL access everywhere"
setfacl -R -m u:cipher:rwxX,u:66536:rwxX /root/docs
find /root/docs -type d -exec setfacl -d -m u:cipher:rwxX,u:66536:rwxX {} +

echo "[3/4] install Kalinga notes from staged tarball"
tar -xzf /cipher/kalinga_notes_20260830.tar.gz -C /root/docs
chown -R 66536:66536 /root/docs
setfacl -R -m u:cipher:rwxX,u:66536:rwxX /root/docs
find /root/docs -type d -exec setfacl -d -m u:cipher:rwxX,u:66536:rwxX {} +

echo "[4/4] verify"
echo "--- projects/ ---"
ls -la /root/docs/projects/ | head -8
echo "--- kalinga/ ---"
ls /root/docs/projects/kalinga/
echo "--- ACL sample on projects/ ---"
getfacl -p /root/docs/projects 2>/dev/null | grep -E '^user:|^default:' || echo "getfacl not found, skipping"
echo "DONE_OK"