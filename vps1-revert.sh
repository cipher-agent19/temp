#!/usr/bin/env bash
# CLEAN REVERT - removes ALL cipher-related setup from VPS1. Run as root.
# Leaves your root docker / Dorn / agent-harness fully untouched.
set -euo pipefail

echo "=== 1. Remove 'Match User cipher' block from sshd_config ==="
sed -i '/^Match User cipher/,/^$/d' /etc/ssh/sshd_config
sshd -t && echo "config OK" || echo "config issue - run: sshd -t"
systemctl reload ssh 2>/dev/null || service ssh reload 2>/dev/null || echo "reload deferred (service name: ssh)"

echo "=== 2. Remove cipher user + home (/cipher) ==="
if id cipher >/dev/null 2>&1; then
  pkill -u cipher 2>/dev/null || true
  sleep 1
  userdel -r cipher && echo "removed cipher user + /cipher"
else
  echo "no cipher user present"
fi

echo "=== 3. Purge rootless-docker helper packages (keeps root docker intact) ==="
export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a 2>/dev/null || true
apt-get purge -y docker-ce-rootless-extras slirp4netns 2>/dev/null && echo "purged rootless helpers" || echo "already clean"
apt-get -f -y install 2>/dev/null || true
apt-get autoremove -y 2>/dev/null | tail -1 || true

echo "REVERT DONE - cipher removed, sshd cleaned, rootless pkgs purged. Root docker & Dorn untouched."
echo "Verify: 'id cipher' should say no such user; /cipher should be gone."
