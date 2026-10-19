// Seed job (run by Configuration-as-Code) that creates the Wonderland/dormouse pipeline.
//
// The pipeline is defined HERE, inline — NOT read from a Jenkinsfile in the repository. It polls the
// dormouse repo over git every minute, and in its test stage it fetches the 3rd-party reportcov.sh
// from the SHARED artifact server and RUNS it — with no integrity check (no checksum pinned or
// verified against the repository). Whatever the artifact server currently serves is what runs here,
// with Wonderland's Global-scope `flag` deploy token bound in the environment. That is CICD-SEC-9
// (Improper Artifact Integrity Validation): a poisoned artifact runs attacker code with the token in
// scope. The consume step is a baked script so the inline pipeline needs no risky quoting.
pipelineJob('wonderland-dormouse') {
    displayName('Wonderland » dormouse (build & test)')
    definition {
        cps {
            sandbox(true)
            script('''
pipeline {
    agent any
    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
    }
    triggers {
        pollSCM('* * * * *')
    }
    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'http://gitea:3000/Wonderland/dormouse.git', credentialsId: 'gitea-jenkins'
            }
        }
        stage('Build & test') {
            steps {
                withCredentials([string(credentialsId: 'flag', variable: 'flag')]) {
                    sh 'sh /usr/local/bin/dormouse-consume'
                }
            }
        }
    }
    post {
        always {
            cleanWs()
        }
    }
}
'''.stripIndent())
        }
    }
}
