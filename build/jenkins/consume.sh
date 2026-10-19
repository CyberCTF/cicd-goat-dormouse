#!/bin/sh
# dormouse-consume: the dormouse pipeline's test-stage helper (baked into the controller image). It
# fetches the 3rd-party reportcov.sh from the SHARED artifact server and runs it — with NO integrity
# check (no checksum pinned or verified against the Cov repository). Whatever the artifact server
# currently serves is what runs here, with the `flag` deploy token bound in the environment by the
# pipeline's withCredentials block. That is CICD-SEC-9: improper artifact integrity validation. The
# legitimate reportcov.sh is benign; a poisoned one runs the attacker's code with the token in scope.
set -eu

echo "dormouse: fetching reportcov coverage uploader from the shared artifact server"
curl -fsS -o reportcov.sh http://prod/reportcov.sh
chmod +x reportcov.sh
echo "dormouse: running reportcov.sh (no integrity check)"
./reportcov.sh
echo "dormouse: done"
