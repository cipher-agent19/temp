#!/usr/bin/env bash
# COMPLETE REBUILD for cipher's limited VPS1 access, using PODMAN ROOTLESS.
# Run as root AFTER vps1-clean-slate.sh. This is the path that works on kernels
# where rootless Docker's netlink/netns creation fails.
# - No daemon, no systemd service (podman needs none)
# - cipher stays unprivileged, isolated from root docker (AdGuard/Dorn)
# - Containers run with host resources
set -euo pipefail

echo "=== PRECHECK: cipher must be GONE (run clean-slate first) ==="
if id cipher >/dev/null 2>&1; then
  echo "ERROR: cipher still exists. Run vps1-clean-slate.sh first."
  exit 1
fi

echo "=== 1. Install podman + rootless deps ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null
apt-get install -y podman fuse-overlayfs uidmap slirp4netns >/dev/null
echo "installed podman, fuse-overlayfs, uidmap, slirp4netns"

echo "=== 2. Create unprivileged user cipher (home /cipher, no sudo, no root docker group) ==="
useradd --create-home --home-dir /cipher --shell /bin/bash --groups "" cipher
echo "created cipher (home /cipher, only group cipher)"

echo "=== 3. Set SSH password for cipher (you'll be prompted) ==="
passwd cipher

echo "=== 4. Enable password SSH for cipher ONLY (Match User), keep global no ==="
sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config 2>/dev/null || true
if ! grep -q '^Match User cipher' /etc/ssh/sshd_config; then
  printf '\nMatch User cipher\n    PasswordAuthentication yes\n' >> /etc/ssh/sshd_config
fi
sshd -t && (service ssh reload || systemctl reload ssh)

echo "=== 5. subuid/subgid + subgid range for podman (65536 IDs) ==="
grep -q "^cipher:" /etc/subuid || usermod --add-subuids 100000-165535 --add-subgids 100000-165535 cipher
grep cipher /etc/subuid /etc/subgid

echo "=== 6. Podman storage for cipher uses fuse-overlayfs (works rootless) ==="
su - cipher -c 'mkdir -p /cipher/.config/containers && cat > /cipher/.config/containers/storage.conf <<EOF
[storage]
driver = "fuse-overlayfs"
[storage.options]
mount_program = "/usr/bin/fuse-overlayfs"
EOF
chmod 600 /cipher/.config/containers/storage.conf'
echo "configured fuse-overlayfs storage"

echo "=== 7. VERIFY podman rootless as cipher (Docker-compatible, no netlink wall) ==="
su - cipher -c 'podman run --rm docker.io/alpine sh -c "echo PODMAN_ROOTLESS_OK CPUs=\$(nproc); free -m | head -2; df -h /"'

echo
echo "=== REBUILD COMPLETE ==="
echo "cipher has: podman (docker-compatible), SSH, host CPU/RAM/disk."
echo "Isolated from root docker (AdGuard/Dorn) + /root. agent-harness stays GitHub-only."
echo
echo "Add this so cipher's later logins have the Docker-compatible alias ready:"
echo 'su - cipher -c '\''echo "alias docker=podman" >> /cipher/.bashrc; echo "export CONTAINER_HOST=unix:///cipher/.docker/run/podman/podman.sock" >> /cipher/.bashrc'\'''
