# reportcov

A tiny, vendor-neutral **coverage report uploader** used in CI by lots of teams. Drop `reportcov.sh`
into your pipeline's test stage and it ships your coverage summary to the Cov service:

```sh
curl -Os http://reportcov.cov.example/reportcov.sh
chmod +x reportcov.sh
./reportcov.sh
```

`reportcov.sh` is built from this repository and published to the Cov artifact server by the
project's release pipeline. Consumers fetch it from there on every build.

> Heads up: pin and verify the script's checksum against this repository before you run it. A build
> that runs `reportcov.sh` straight off the network trusts whatever the artifact server happens to be
> serving.
