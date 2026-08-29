#!/usr/bin/env bash
# CLEAN SETUP v2 - rights-restricted agent access on VPS1. Run as root.
# Corrects v1 issues: scoped SSH auth (Match User), correct service reload,
# no global password flip, clean apt handling. Does NOT touch root docker/Dorn.
set -euo pipefail

USER=cipher
HOMEDIR=/cipher
AGENT_PUBKEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICok1q0NqJw/K3N/bBNarJriMlw7PYpNGRH5ttTJlN0p hermes-box'

echo "=== 1. Create user $USER (home $HOMEDIR, no sudo/docker groups) ==="
if ! id "$USER" >/dev/null 2>&1; then
  useradd --create-home --home-dir "$HOMEDIR" --shell /bin/bash --groups "" "$USER"
  echo "created $USER"
else
  echo "$USER exists (not modifying)"
fi

echo "=== 2. Set SSH password for $USER (interactive) ==="
passwd "$USER"

echo "=== 3. Add agent pubkey for $USER (key-based SSH backup) ==="
install -d -m 700 -o "$USER" -g "$USER" "$HOMEDIR/.ssh"
grep -qF "$AGENT_PUBKEY" "$HOMEDIR/.ssh/authorized_keys" 2>/dev/null || \
  echo "$AGENT_PUBKEY" > "$HOMEDIR/.ssh/authorized_keys"
chown -R "$USER:$USER" "$HOMEDIR/.ssh"
chmod 600 "$HOMEDIR/.ssh/authorized_keys"

echo "=== 4. Scope password SSH to $USER ONLY (Match User, keep global 'no') ==="
# Ensure global PasswordAuthentication is 'no' unless already explicitly allowed
if grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config; then
  sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
  echo "set global PasswordAuthentication to 'no'"
fi
if ! grep -q "Match User $USER" /etc/ssh/sshd_config; then
  printf '\nMatch User %s\n  PasswordAuthentication yes\n' "$USER" >> /etc/ssh/sshd_config
  echo "scoped password auth to $USER"
fi
sshd -t && echo "sshd config OK" || { echo "sshd CONFIG ERROR"; exit 1; }
systemctl reload ssh 2>/dev/null || service ssh reload 2>/dev/null || echo "reload deferred"

echo "=== 5. Fix any interrupted package state + install rootless docker support ==="
export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a 2>/dev/null || true
apt-get install -f -y 2>/dev/null || true
apt-get update -y >/dev/null 2>&1 || true
if ! command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1; then
  apt-get install -y uidmap slirp4netns docker-ce-rootless-extras 2>/dev/null || \
    echo "NOTE: manual install needed: apt-get install uidmap slirp4netns docker-ce-rootless-extras"
fi

echo "=== 6. Install rootless daemon AS $USER ==="
su - "$USER" -c 'export PATH=/usr/bin:$PATH; dockerd-rootless-setuptool.sh install' 2>&1 | tail -3 || \
  echo "NOTE: run 'dockerd-rootless-setuptool.sh install' as $USER manually"

echo
echo "=== VERIFY ==="
echo "groups of $USER: $(groups "$USER")"
echo "sshd PasswordAuthentication (global, want 'no'): $(sshd -T 2>/dev/null | grep -i '^passwordauthentication' || echo n/a)"
echo "DONE. Proceed to WireGuard + Netdata steps."
