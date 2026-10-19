# Dormouse: improper artifact integrity validation (CyberCTF lab)

A bespoke, self-contained reproduction of the **Dormouse** challenge from
[CI/CD Goat](https://github.com/cider-security-research/cicd-goat) — OWASP **CICD-SEC-8, Ungoverned
Usage of 3rd Party Services** and **CICD-SEC-9, Improper Artifact Integrity Validation**. Inspired by
the Codecov incident: a 3rd-party script hosted on a shared artifact server is hijacked, and
pipelines that run it without verifying its integrity execute the attacker's code.

`Cov/reportcov` is a 3rd-party coverage tool. Its Jenkins pipeline (which you cannot view) publishes
an artifact, `reportcov.sh`, to a **shared artifact server**. Wonderland's own pipeline,
`wonderland-dormouse`, downloads that `reportcov.sh` and runs it in its test stage **without
verifying it**, with Wonderland's deploy token (a Jenkins credential at Global scope) bound. The
reportcov pipeline interpolates an attacker-controlled commit field into a shell command (command
injection) and holds the artifact server's SSH key. An attacker with write access to reportcov steals
the key, `scp`s a **poisoned** `reportcov.sh` onto the shared server, and triggers the dormouse
pipeline — which runs the attacker's code and leaks the token to the build console.

**Private lab content — do not copy into any public repository.**

## Infrastructure

Three machines, the minimum this supply-chain attack needs:

| Machine | What |
|---|---|
| `jenkins` | Jenkins controller, configured by Configuration-as-Code. A Job DSL seed creates two **inline** (unviewable) pipelines, each a git poll (1-minute): `cov-reportcov` binds the artifact-server SSH key (`artifact-key`) and interpolates the latest commit subject into a shell command (the injection); `wonderland-dormouse` binds the Global-scope `flag` token and runs whatever `reportcov.sh` the shared server serves. `git`, `curl`, `ssh`/`scp` are present for the solver. |
| `gitea` | Gitea git host. The setup job provisions the `Cov` org + public `reportcov` repo (attacker `alice` = write, poller `jenkins` = read) and the `Wonderland` org + private `dormouse` repo (`jenkins` = read), then pushes both sample projects. |
| `prod` | The **shared artifact server** — the ungoverned 3rd-party service. Serves `reportcov.sh` over HTTP (busybox httpd, :80) and accepts deployments over SSH (sshd, :22, root, key-only). No integrity controls: whatever is uploaded is what downstream runs. |

The web ports listen on container `8080` (Jenkins), `3000` (Gitea) and `80` (prod); prod's SSH is on
container `22`. All host ports are assigned dynamically by the runner. Jenkins is slow to boot — allow
a few minutes.

## Objective

One per-player objective (`.ctf/objectives.json`), graded by CyberBackend:

| Key | Evidence | What the player recovers |
|---|---|---|
| `dormouse` | `SECRET` (`%s`) | Wonderland's deploy token, exfiltrated by the dormouse pipeline after the shared `reportcov.sh` artifact was poisoned |

Intended path: clone `Cov/reportcov` (write creds) → push a commit whose **subject** injects a command
that reads the bound artifact-server key `$KEY` and prints it past the mask (`echo $KEY | rev |
base64`) → recover the key (`base64 -d | rev`) → `scp` a poisoned `reportcov.sh`
(`echo "$flag" | rev | base64`) onto the shared server → build `wonderland-dormouse` → read the
console and recover the token (`base64 -d | rev`). The recovered token is the flag. (Modern Jenkins
masks a bound secret's raw value *and* its plain base64; reversing first evades the masker — see
UPSTREAM.md.)

## Per-player flag

The flag is issued per player by CyberCTF and handed to the lab by the launcher as a **file**
(`isoloom.yml` `inputs: [CTF_FLAG_DORMOUSE]`, delivered via
`files: [{ path: /run/lab/secrets/flag, input: CTF_FLAG_DORMOUSE }]` on the Jenkins machine), never an
environment variable, so it never appears in `docker inspect`, an image layer or a generated file. The
Jenkins entrypoint stages the file into the directory JCasC reads file secrets from, so `flag`
(`secret: "${flag}"`) resolves at boot **into the credential store only** — a pipeline must bind the
credential to read it. An **offline start** (local, CI) leaves the input empty and the lab stages its
development placeholder (`.ctf/objectives.json` `dev`) instead, so it still comes up and is solvable.

The artifact server's SSH key is a **fixed lab value** (a fixed ed25519 keypair): the private key
(base64) is a Jenkins credential `artifact-key`, the public key is baked into prod's `authorized_keys`.
It is the secret the attacker **steals**, not the per-player flag.

## Dynamic ports

Every published port declares `publish: true`, so the runner picks a **free host port at `up` time** —
there is no fixed host port anywhere in the spec, message, configs or checks (the only literals are
in-container loopback/ports and the lab network CIDR `10.43.0.0/24`). The `message` reads the real
values back through `{{ machines.*.ports.*.url }}` and `{{ machines.prod.ports.ssh.published }}`.

## Run it

Described once in [`isoloom.yml`](isoloom.yml) ([Isoloom](https://www.isoloom.com)); run on Docker
through the [Isothrum](https://www.isothrum.com) runner:

```bash
isoloom validate .
isoloom generate . --target docker
isothrum up . --target docker          # add --secret-from-env CTF_FLAG_DORMOUSE for a real value
isothrum check . --target docker       # Jenkins is slow; the solver drives two pipelines
isothrum down . --target docker
```

## Layout

- `build/jenkins/` — Jenkins LTS + plugins (runs as root to read the mounted secret), JCasC with the
  three credentials, the two inline pipelines (`casc/jobdsl/{reportcov,dormouse}.groovy`), the
  consume helper (`consume.sh` → `/usr/local/bin/dormouse-consume`), and the solver (`solve.sh` →
  `/usr/local/bin/dormouse-solve`)
- `build/gitea/` — the installed Gitea host, its `setup` seed (`seed.sh`) and the two sample sources
  under `repo-src/`
- `build/prod/` — the shared artifact server (Alpine + sshd + busybox httpd), its `authorized_keys`
  (fixed public key) and the baked benign `reportcov.sh`
- `.ctf/` — `metadata.json` and `objectives.json` (the catalogue registration)
- `UPSTREAM.md` — attribution and the faithful deviations
- `.isoloom/` — generated by `isoloom generate` (git-ignored; don't edit)
