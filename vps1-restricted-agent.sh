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

echo "=== 3. Enable password SSH for $USER ONLY (Match User block) ==="
# IMPORTANT SECURITY FIX (from audit): do NOT flip the GLOBAL PasswordAuthentication
# switch - that would expose every user to password brute-force. Scope it to cipher only.
if ! grep -q "Match User $USER" /etc/ssh/sshd_config; then
  printf '\nMatch User %s\n  PasswordAuthentication yes\n' "$USER" >> /etc/ssh/sshd_config
  echo "added 'Match User $USER  PasswordAuthentication yes'"
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

echo "=== 6b. OPTIONAL: restrict cipher's outbound network (egress leak guard, from audit) ==="
cat <<'EGRESS'
Audit flagged unrestricted egress as a medium/high exfiltration risk (if cipher ever
reads a secret, it could send it out). Two ways to handle it:

  OPTION 1 - leave egress open (DEFAULT, easiest):
    cipher needs general outbound to pull docker images and reach Google APIs
    for its containers. Restricting egress largely defeats that purpose.
    This is an informed tradeoff - acceptable if you trust cipher's rootless
    containers to only do work you intend.

  OPTION 2 - restrict cipher's outbound (hardening):
    Run as root. Blocks cipher's outgoing except loopback, DNS, and SSH to the mesh.
      iptables -A OUTPUT -m owner --uid-owner cipher -o lo -j ACCEPT
      iptables -A OUTPUT -m owner --uid-owner cipher -p udp --dport 53 -j ACCEPT
      iptables -A OUTPUT -m owner --uid-owner cipher -d 10.7.0.0/24 -p tcp --dport 22 -j ACCEPT
      iptables -A OUTPUT -m owner --uid-owner cipher -j REJECT
    Do NOT run this if cipher's containers need the internet.
    NOTE: rootless docker egress goes through slirp4netns (rootlesskit) running
    as cipher, so these owner-uid rules DO apply to cipher's containers.
Decide which BEFORE granting access.
EGRESS

echo "=== 7. Netdata bind to localhost ONLY (cipher-only access, from audit) ==="
echo "Netdata dashboard (19999) must NOT bind publicly. Edit /etc/netdata/netdata.conf:"
cat <<'NETDATA'
  [web]
    bind to = 127.0.0.1
Restart: systemctl restart netdata
Access ONLY via SSH tunnel as cipher (never open 19999 publicly):
  ssh -L 19999:127.0.0.1:19999 cipher@10.7.0.1   # then browser -> http://127.0.0.1:19999
NETDATA

echo
echo "=== VERIFY ==="
echo "--- groups (should be ONLY cipher) ---"; groups "$USER"
echo "--- sudo blocked ---"; sudo -n -u "$USER" sudo id 2>&1 | head -1
echo "--- root blocked ---"; sudo -n -u "$USER" ls /root 2>&1 | head -1
echo "DONE."
