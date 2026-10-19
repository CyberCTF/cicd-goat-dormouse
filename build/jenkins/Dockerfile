# The Jenkins controller. Configured entirely by Configuration-as-Code (casc/jenkins.yaml) with a
# Job DSL seed that creates the two inline pipelines (reportcov + dormouse) — defined in Jenkins, not
# read from any Jenkinsfile, so the player cannot view or edit them. The flag is NOT here: the `flag`
# credential resolves at boot from a file the entrypoint stages out of the per-player input Isoloom
# mounts at run time. The artifact server's SSH key IS here (a fixed lab credential, base64). Runs as
# root so the entrypoint can read the root-only mounted secret; builds run on the controller's own
# executor (`agent any`), which is where the command injection and the artifact consumption land.
FROM jenkins/jenkins:lts-jdk21

USER root

# git + curl for the solver and SCM polling; openssh-client provides scp/ssh so a build (and the
# solver) can deploy to the artifact server once it holds the key; util-linux provides `rev` for the
# masking-evasion transform.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates openssh-client \
 && rm -rf /var/lib/apt/lists/*

# Plugins (resolved for this controller version).
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Configuration-as-Code + the Job DSL seed, outside JENKINS_HOME so they are read as-is at boot.
COPY casc/ /usr/share/jenkins/casc/

COPY entrypoint.sh /usr/local/bin/dormouse-jenkins-entrypoint.sh
COPY consume.sh /usr/local/bin/dormouse-consume
COPY solve.sh /usr/local/bin/dormouse-solve
RUN chmod 0755 /usr/local/bin/dormouse-jenkins-entrypoint.sh /usr/local/bin/dormouse-consume /usr/local/bin/dormouse-solve

ENV CASC_JENKINS_CONFIG=/usr/share/jenkins/casc/jenkins.yaml \
    SECRETS=/run/lab/casc_secrets \
    JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Xmx1024m"

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/dormouse-jenkins-entrypoint.sh"]
