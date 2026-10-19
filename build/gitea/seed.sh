#!/bin/sh
# Isoloom `setup` step for the Gitea machine (runs once, after Gitea is healthy, in the Gitea image,
# sharing its network namespace so Gitea is reachable at 127.0.0.1:3000). It provisions the two
# repositories over the Gitea API and pushes their baked sample sources:
#   - org `Cov` (public), repo `reportcov` (public)  -> the 3rd-party coverage tool
#   - org `Wonderland` (private), repo `dormouse` (private) -> Wonderland's consumer app
#   - `alice`   (the attacker) with WRITE access on reportcov  -> used by the player / the solver
#   - `jenkins` with READ access on both                       -> used by Jenkins to poll the repos
# No challenge secret is handled here; the flag is a Jenkins credential injected elsewhere, and the
# artifact server's key is a separate fixed lab value baked into the jenkins and prod images.
set -eu

BASE="${GITEA_BASE_URL:-http://127.0.0.1:3000}"
ADMIN_USER="${GITEA_ADMIN_USER:-wonderland_admin}"
ADMIN_PASS="${GITEA_ADMIN_PASS:-W0nderland-admin}"
SRC="${DORMOUSE_SRC:-/opt/repo-src}"

ATTACKER_USER="alice"
ATTACKER_PASS="alice"
CI_USER="jenkins"
CI_PASS="jenkins"

AUTH="$ADMIN_USER:$ADMIN_PASS"
API="$BASE/api/v1"

log() { echo "seed: $1"; }

# POST/PUT JSON as admin; tolerate 'already exists' (409/422) so the job is idempotent on restart.
api() {  # method path json
  if [ -n "${3:-}" ]; then
    code=$(curl -s -o /tmp/seed.out -w '%{http_code}' -X "$1" \
           -H 'Content-Type: application/json' -u "$AUTH" \
           --data "$3" "$API$2" 2>/dev/null || echo 000)
  else
    code=$(curl -s -o /tmp/seed.out -w '%{http_code}' -X "$1" -u "$AUTH" "$API$2" 2>/dev/null || echo 000)
  fi
  case "$code" in
    2*) return 0 ;;
    409|422) log "exists ($code): $1 $2"; return 0 ;;
    *) log "WARN $code: $1 $2 -> $(tr -d '\n' < /tmp/seed.out | cut -c1-200)"; return 1 ;;
  esac
}

# Push a baked source tree to a repo's main (idempotent via caller's branch check).
push_repo() {  # org repo src_subdir message
  _org="$1"; _repo="$2"; _sub="$3"; _msg="$4"
  WORK="$(mktemp -d)"
  cp -a "$SRC/$_sub/." "$WORK/"
  cd "$WORK"
  export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME="Cov Maintainer" GIT_AUTHOR_EMAIL="maintainer@cov.example"
  export GIT_COMMITTER_NAME="Cov Maintainer" GIT_COMMITTER_EMAIL="maintainer@cov.example"
  export GIT_AUTHOR_DATE="2024-02-01T09:00:00" GIT_COMMITTER_DATE="2024-02-01T09:00:00"
  git -c init.defaultBranch=main init -q
  git add -A
  git commit -q -m "$_msg"
  git push -q "http://$ADMIN_USER:$ADMIN_PASS@127.0.0.1:3000/$_org/$_repo.git" main
  cd /
  rm -rf "$WORK"
}

# 1. Wait for the Gitea API.
i=0
while :; do
  c=$(curl -s -o /dev/null -w '%{http_code}' "$API/version" 2>/dev/null || echo 000)
  [ "$c" = "200" ] && break
  i=$((i+1)); [ "$i" -lt 120 ] || { log "FATAL: Gitea API never answered"; exit 1; }
  sleep 2
done
log "Gitea API is up"

# 2. Idempotency: if reportcov already has a main branch, everything below is already done.
c=$(curl -s -o /dev/null -w '%{http_code}' -u "$AUTH" "$API/repos/Cov/reportcov/branches/main" 2>/dev/null || echo 000)
if [ "$c" = "200" ]; then
  log "repositories already seeded; nothing to do"
  exit 0
fi

# 3. Users.
api POST "/admin/users" "{\"username\":\"$ATTACKER_USER\",\"email\":\"alice@cov.example\",\"password\":\"$ATTACKER_PASS\",\"must_change_password\":false}"
api POST "/admin/users" "{\"username\":\"$CI_USER\",\"email\":\"jenkins@wonderland.example\",\"password\":\"$CI_PASS\",\"must_change_password\":false}"

# 4. The 3rd-party Cov/reportcov (public) — alice writes (attacker), jenkins reads (poller).
api POST "/orgs" "{\"username\":\"Cov\",\"visibility\":\"public\"}"
api POST "/orgs/Cov/repos" "{\"name\":\"reportcov\",\"private\":false,\"auto_init\":false,\"default_branch\":\"main\"}"
api PUT "/repos/Cov/reportcov/collaborators/$ATTACKER_USER" "{\"permission\":\"write\"}"
api PUT "/repos/Cov/reportcov/collaborators/$CI_USER" "{\"permission\":\"read\"}"

# 5. Wonderland/dormouse (private) — jenkins reads (poller); alice may read (exploration).
api POST "/orgs" "{\"username\":\"Wonderland\",\"visibility\":\"private\"}"
api POST "/orgs/Wonderland/repos" "{\"name\":\"dormouse\",\"private\":true,\"auto_init\":false,\"default_branch\":\"main\"}"
api PUT "/repos/Wonderland/dormouse/collaborators/$CI_USER" "{\"permission\":\"read\"}"
api PUT "/repos/Wonderland/dormouse/collaborators/$ATTACKER_USER" "{\"permission\":\"read\"}"

# 6. Push the baked sample sources to main.
push_repo Cov reportcov reportcov "Initial import of the reportcov coverage tool"
push_repo Wonderland dormouse dormouse "Initial import of the dormouse service and its CI"

log "seeded: Cov/reportcov (alice=write, jenkins=read) + Wonderland/dormouse (jenkins=read)"
