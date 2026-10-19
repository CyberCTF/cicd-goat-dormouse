#!/bin/sh
# reportcov — the coverage uploader, as currently published on the Cov artifact server. Consumers
# fetch this over HTTP and run it in their CI test stage. The legitimate build is benign: it does not
# read any consumer secret. (Whatever bytes this server holds are what consumers run — there is no
# integrity control, which is the whole point of the challenge.)
echo "reportcov: collecting coverage summary"
echo "reportcov: coverage report uploaded to the Cov service — ok"
