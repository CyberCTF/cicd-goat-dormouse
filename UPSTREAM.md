# Upstream

This lab reproduces one challenge — **Dormouse** — from CI/CD Goat.

| What | Source | Licence |
| --- | --- | --- |
| The "Dormouse" challenge (poison a shared 3rd-party artifact via a stolen deploy key + command injection; a downstream pipeline runs it without integrity validation) | [CI/CD Goat](https://github.com/cider-security-research/cicd-goat) by Cider Security (now Palo Alto Networks) | Apache-2.0 |
| Security classes | [OWASP CICD-SEC-8: Ungoverned Usage of 3rd Party Services](https://owasp.org/www-project-top-10-ci-cd-security-risks/CICD-SEC-08-Ungoverned-Usage-of-3rd-Party-Services) and [CICD-SEC-9: Improper Artifact Integrity Validation](https://owasp.org/www-project-top-10-ci-cd-security-risks/CICD-SEC-09-Improper-Artifact-Integrity-Validation) | — |
| Theme | The [Codecov incident](https://about.codecov.io/security-update/) | — |

Only the *vulnerability chain* is reproduced, not upstream's full multi-machine CI/CD stack. The lab
is three machines — a Jenkins controller, a Gitea git host and a shared artifact server — which is the
minimum this attack needs: a 3rd-party pipeline that holds a deploy key and is command-injectable, a
shared artifact server with no integrity controls, and a downstream pipeline that runs the artifact
with a secret bound.

Nothing is vendored from upstream. The sample repositories (`build/gitea/repo-src/reportcov`,
`.../dormouse`) are **original** minimal projects authored here (no third-party code — upstream serves
a copy of `flask_meld`). The per-player flag is injected into the Jenkins credential store at run time
(upstream bakes one fixed UUID), so each player exfiltrates their own flag. The artifact server's SSH
key is a **fixed lab keypair** generated for this lab (not upstream's).

## The attack chain (faithful to the upstream write-up)

Upstream `app/solutions/dormouse.md`:

1. command injection via the reportcov pipeline's handling of an attacker-controlled field
   (`sh "echo Pull Request ${title} ..."`) to read `$KEY`, the artifact server's key, and exfiltrate
   it to the attacker;
2. use `$KEY` to `scp` a malicious `reportcov.sh` onto the artifact server;
3. run the dormouse pipeline, which fetches and runs `reportcov.sh` with the flag credential bound;
4. read the console for the secret.

This lab reproduces every step.

## Faithful deviations

- **Trigger.** Upstream fires the reportcov pipeline with the Jenkins Gitea **generic webhook** and
  reads the attacker-controlled field from the webhook payload (`$.pull_request.title` via JSONPath).
  This lab uses a version-robust **git poll** (1-minute `pollSCM`, no inbound webhook) and takes the
  attacker-controlled field from the latest **commit subject** instead of a PR title. The vulnerability
  class is identical (untrusted VCS metadata interpolated into a shell command — the exact upstream
  line pattern `sh "echo ... ${field} ..."`), and the player's steps are the same (push a crafted
  change to `Cov/reportcov`). Dropping the Jenkins↔Gitea plugin/webhook dependency matters for a lab
  family meant to run unattended. The solver also nudges a build via the Jenkins API so the self-check
  is deterministic.

- **Key handling / exfiltration endpoint.** Upstream holds `$KEY` as a plain job env var and the
  injection exfiltrates it to "YOUR SERVER" (the attacker's host). This lab holds `$KEY` as a Jenkins
  **credential** (so it is encrypted at rest and masked in the console — a truer modern setup), and the
  injection drops it onto the controller itself, which is the attacker's foothold / the solver's
  vantage point. A human solver recovers it from the build console with a masking-evasion transform
  (`echo $KEY | rev | base64`, then `base64 -d | rev`), exactly as for the flag.

- **Artifact server.** Upstream runs the artifact server in the single-host compose and reaches it at
  `localhost:2222`. Here it is a separate machine (`prod`) reached at `prod:22` over the lab network; a
  dynamic host port is published so a human can `scp` from their own host. It is a minimal Alpine
  image (openssh `sshd` for the deploy channel + `darkhttpd`, a tiny config-free static server, for
  serving the artifact over HTTP — Alpine's busybox has no `httpd` applet), standing in for whatever
  artifact service a team might use.

## A note on masking (the exfiltration encoding)

Upstream's solution prints `echo $FLAG | base64`, relying on base64 slipping past credential masking.
On the modern Jenkins this lab ships, the `credentials-binding` plugin masks a bound secret's raw value
**and its plain base64**, so that exact trick no longer works. The lab keeps the vulnerability
identical and only updates the encoding to one the masker does not precompute — reversing before
base64 (`echo $x | rev | base64`, recover with `base64 -d | rev`). This is used both for the stolen
key and for the flag. It is arguably a truer lesson for current CI: masking is a best-effort guardrail,
not a control.
