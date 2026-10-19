# The shared artifact server (`prod`) — the ungoverned 3rd-party service (CICD-SEC-8). It holds the
# reportcov.sh artifact and has NO integrity controls: it serves whatever bytes it currently stores
# over HTTP (busybox httpd on :80), and accepts deployments over SSH (sshd on :22) for root, by key
# only, using the FIXED lab public key baked below. The matching private key is a FIXED lab value
# held as a Jenkins credential on the controller (NOT the per-player flag). A benign reportcov.sh is
# baked in; the attack replaces it. No challenge flag ever lives here.
FROM alpine:3.20

# openssh (meta) brings sshd + scp + the sftp subsystem, so both legacy and modern scp clients work;
# darkhttpd is a tiny, config-free static file server for the artifact over HTTP.
RUN apk add --no-cache openssh darkhttpd \
 && ssh-keygen -A \
 && mkdir -p /root/.ssh /var/www/localhost/htdocs /var/empty \
 && chmod 0700 /root/.ssh

COPY sshd_config /etc/ssh/sshd_config
COPY authorized_keys /root/.ssh/authorized_keys
COPY htdocs/reportcov.sh /var/www/localhost/htdocs/reportcov.sh
COPY entrypoint.sh /usr/local/bin/prod-entrypoint.sh
RUN chmod 0600 /root/.ssh/authorized_keys \
 && chmod 0644 /var/www/localhost/htdocs/reportcov.sh \
 && chmod 0755 /usr/local/bin/prod-entrypoint.sh \
 && chmod 0644 /etc/ssh/sshd_config

EXPOSE 22 80
ENTRYPOINT ["/usr/local/bin/prod-entrypoint.sh"]
