#!/usr/bin/env bash
# Starts a throwaway sshd container on 127.0.0.1:2222 for the ssh-deploy tests.
# Usage: tests/sshd-up.sh <keydir>. Writes client and host keypairs into <keydir>.
set -euo pipefail

keydir="${1:?usage: sshd-up.sh <keydir>}"
container=ssh-deploy-test
image='ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852'

ssh-keygen -q -t ed25519 -N '' -C client -f "$keydir/client"
ssh-keygen -q -t ed25519 -N '' -C host -f "$keydir/host"

docker rm -f "$container" >/dev/null 2>&1 || true
docker run -d --name "$container" -p 127.0.0.1:2222:22 -v "$keydir:/keys:ro" "$image" bash -ec '
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -qq -y --no-install-recommends openssh-server >/dev/null
  useradd -m -s /bin/bash deploy
  install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
  install -m 600 -o deploy -g deploy /keys/client.pub /home/deploy/.ssh/authorized_keys
  install -m 600 /keys/host /etc/ssh/ssh_host_ed25519_key
  mkdir -p /run/sshd
  exec /usr/sbin/sshd -D -e -h /etc/ssh/ssh_host_ed25519_key -o PasswordAuthentication=no
' >/dev/null

for _ in $(seq 1 120); do
  if ssh-keyscan -p 2222 -t ed25519 127.0.0.1 2>/dev/null | grep -q ssh-ed25519; then
    exit 0
  fi
  sleep 1
done
docker logs "$container" >&2
echo "sshd did not come up" >&2
exit 1
