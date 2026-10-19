#!/bin/sh
# Artifact server entrypoint. Serves the artifact directory over HTTP (busybox httpd) and runs sshd
# for the deploy channel. No secret here; the served file is whatever has been uploaded.
set -eu

# Host keys exist from build; regenerate only if somehow missing.
[ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -A

# Serve the artifact directory over HTTP in the background (darkhttpd: tiny, no config).
/usr/bin/darkhttpd /var/www/localhost/htdocs --addr 0.0.0.0 --port 80 &

# Run sshd in the foreground (PID 1 for clean shutdown).
exec /usr/sbin/sshd -D -e
