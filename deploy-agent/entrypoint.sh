#!/bin/sh
set -e

# Inject the SSH public key passed via AUTHORIZED_KEY env var
if [ -n "${AUTHORIZED_KEY}" ]; then
  echo "${AUTHORIZED_KEY}" > /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
fi

exec /usr/sbin/sshd -D -e
