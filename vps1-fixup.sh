#!/usr/bin/env bash
# FIXUP for an already-run v1 install of vps1-restricted-agent.sh.
# The v1 script enabled GLOBAL password SSH (security regression flagged by audit).
# This script:
#   1. Reverts the global PasswordAuthentication back to 'no'
#   2. Applies a scoped 'Match User cipher  PasswordAuthentication yes' instead
#   3. Re-checks that cipher is NOT in sudo/docker groups
# Run as root on VPS1.
set -euo pipefail
USER=cipher

echo "=== 1. Revert GLOBAL PasswordAuthentication to no ==="
if grep -q '^PasswordAuthentication yes' /etc/ssh/sshd_config; then
  sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
  echo "reverted global PasswordAuthentication to 'no'"
else
  echo "global PasswordAuthentication was already 'no' or unset (good)"
fi

echo "=== 2. Ensure scoped Match User block for $USER ==="
if ! grep -q "Match User $USER" /etc/ssh/sshd_config; then
  printf '\nMatch User %s\n  PasswordAuthentication yes\n' "$USER" >> /etc/ssh/sshd_config
  echo "added 'Match User $USER  PasswordAuthentication yes'"
else
  echo "Match User $USER block already present"
fi

echo "=== 3. Test sshd config, then reload ==="
sshd -t && echo "sshd config OK" && (systemctl reload sshd || service ssh reload)

echo "=== 4. Confirm cipher has NO elevated groups ==="
echo "groups of $USER: $(groups "$USER")"
G=$(groups "$USER")
if echo "$G" | grep -qE '(sudo|wheel|docker)'; then
  echo "WARNING: $USER is in a privileged group ($G). Remove it!"
else
  echo "OK: $USER has no sudo/wheel/docker group"
fi
echo "DONE."
