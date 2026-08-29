#!/usr/bin/env bash
# COMPLETE CLEANUP of the VPS1 agent-access experiment. Run as root.
# Removes EVERYTHING we touched. Leaves your root docker, AdGuard, Dorn, and
# agent-harness fully untouched.
set -euo pipefail

echo "=== 1. Stop + disable rootless docker systemd service ==="
systemctl stop docker-rootless-cipher.service 2>/dev/null || true
systemctl disable docker-rootless-cipher.service 2>/dev/null || true
rm -f /etc/systemd/system/docker-rootless-cipher.service
rm -f /etc/systemd/system/multi-user.target.wants/docker-rootless-cipher.service
rm -rf /etc/systemd/system/docker-rootless-cipher.service.d
systemctl daemon-reload

echo "=== 2. Kill any lingering rootless processes ==="
pkill -u cipher -f dockerd-rootless 2>/dev/null || true
pkill -u cipher -f rootlesskit 2>/dev/null || true
pkill -u cipher -f dockerd 2>/dev/null || true
pkill -u cipher -f containerd 2>/dev/null || true

echo "=== 3. Remove daemon config + runtime dirs ==="
rm -rf /cipher/.config /cipher/.docker /cipher/.local/share/docker /cipher/.cache

echo "=== 4. Remove sshd Match User block for cipher (if added) ==="
sed -i '/^Match User cipher$/,+2d' /etc/ssh/sshd_config 2>/dev/null || true
sshd -t && (service ssh reload || systemctl reload ssh) 2>/dev/null || echo "note: restart sshd manually"

echo "=== 5. Remove subuid/subgid entries for cipher ==="
sed -i '/^cipher:/d' /etc/subuid /etc/subgid 2>/dev/null || true

echo "=== 6. Remove cipher user + home ==="
userdel -r cipher 2>/dev/null || echo "note: cipher user not found, continuing"
rm -rf /cipher

echo "=== 7. Remove Docker apt repo + rootless packages (keeps your root docker daemon!) ==="
rm -f /etc/apt/sources.list.d/docker.list
rm -f /etc/apt/keyrings/docker.asc
apt-get remove -y docker-ce-rootless-extras 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true

echo
echo "=== CLEAN SLATE COMPLETE ==="
echo "Removed: cipher user, /cipher, rootless docker service+pkgs, docker repo,"
echo "sshd Match User block, subuid/subgid, daemon config."
echo "UNTOUCHED: your root docker daemon (AdGuard, Dorn), /root, agent-harness."
echo
echo "--- verify: cipher gone ---"
id cipher 2>&1 || echo "OK: cipher does not exist"
echo "--- verify: root docker untouched ---"
docker ps 2>&1 | head -3
