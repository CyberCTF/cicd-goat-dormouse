# dormouse

A small Wonderland service. Nothing exciting — it keeps a sleepy little state machine and a couple
of helpers. What matters for CI is the test stage: it pulls in the 3rd-party **reportcov** coverage
uploader from the Cov artifact server and runs it, exactly as many teams do.

```sh
pip install -r requirements.txt
pytest
# then: curl -Os http://reportcov.cov.example/reportcov.sh && ./reportcov.sh
```

The pipeline that builds this repository is defined on the CI controller, not here.
