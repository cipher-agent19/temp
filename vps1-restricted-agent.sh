#!/usr/bin/env bash
# Simplified rights-restricted SSH user for the Hermes agent on VPS1.
# Run as root on VPS1.
# - User 'cipher', home /cipher
# - Password SSH (you'll be prompted to set it)
# - NO sudo, NOT in root docker group
# - Rootless docker so cipher gets own isolated containers (can't touch yours)
# - Root containers are monitored via a SEPARATE lightweight app (not cipher's docker)
set -euo pipefail

USER=cipher
HOMEDIR=/cipher

echo "=== 1. Create user (no sudo, no docker group) ==="
if ! id "$USER" >/dev/null 2>&1; then
  useradd --create-home --home-dir /cipher --shell /bin/bash --groups "" "$USER"
fi
echo "created / existing user: $USER (home: $HOMEDIR)"

echo "=== 2. Set SSH password for $USER ==="
passwd "$USER"    # prompts for a password - this is what Cipher uses to SSH

echo "=== 3. Allow password SSH (enable PasswordAuthentication) ==="
# Only edit if /etc/ssh/sshd_config has it disabled. Usually needs:
#   PasswordAuthentication yes
if grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config; then
  sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
  echo "enabled PasswordAuthentication"
  systemctl reload sshd || service ssh reload
fi

echo "=== 4. Install rootless docker support ==="
command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1 || {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y >/dev/null
  apt-get install -y uidmap slirp4netns docker-ce-rootless-extras >/dev/null
  echo "installed rootless-docker helper tools"
}

echo "=== 5. Install the isolated rootless daemon AS cipher ==="
su - "$USER" -c 'export PATH=/usr/bin:$PATH; command -v dockerd-rootless-setuptool.sh && dockerd-rootless-setuptool.sh install' || \
  echo "NOTE: run 'dockerd-rootless-setuptool.sh install' as $USER manually"

echo "=== 6. Rootless docker socket location (for Netdata monitoring) ==="
echo "Expected rootless socket: /cipher/.docker/run/docker.sock (NOT /home/cipher/... because home is /cipher)"

echo
echo "=== VERIFY ==="
echo "--- groups (should be ONLY cipher) ---"; groups "$USER"
echo "--- sudo blocked ---"; sudo -n -u "$USER" sudo id 2>&1 | head -1
echo "--- root blocked ---"; sudo -n -u "$USER" ls /root 2>&1 | head -1
echo "DONE."
