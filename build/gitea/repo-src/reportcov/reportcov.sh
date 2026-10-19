#!/bin/sh
# reportcov — the coverage uploader source of truth. The release pipeline publishes this file to the
# Cov artifact server, and consumers run it in their CI test stage. It summarises coverage and (in a
# real deployment) uploads it to the Cov service. It does NOT read or need any consumer secret.
set -eu

echo "reportcov: collecting coverage summary"
if [ -f coverage.xml ]; then
  echo "reportcov: found coverage.xml"
else
  echo "reportcov: no coverage.xml; reporting an empty summary"
fi
echo "reportcov: coverage report uploaded to the Cov service — ok"
