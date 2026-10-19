# The git host: Gitea, configured for the lab (installed, HTTP only, SQLite on the /data volume).
# The repositories are NOT baked into the image: their sample sources are staged at /opt/repo-src and
# pushed into Gitea at run time by the Isoloom setup job (seed.sh), which also creates the orgs and
# users. No challenge secret lives here.
FROM gitea/gitea:1.22

ENV GITEA_WORK_DIR=/data \
    GITEA_ADMIN_USER=wonderland_admin \
    GITEA_ADMIN_PASS=W0nderland-admin

COPY app.ini /etc/gitea/app.ini
COPY repo-src/ /opt/repo-src/
COPY entrypoint.sh /usr/local/bin/dormouse-gitea-entrypoint.sh
RUN chmod 0755 /usr/local/bin/dormouse-gitea-entrypoint.sh && chmod 0644 /etc/gitea/app.ini

EXPOSE 3000
ENTRYPOINT ["/usr/local/bin/dormouse-gitea-entrypoint.sh"]
