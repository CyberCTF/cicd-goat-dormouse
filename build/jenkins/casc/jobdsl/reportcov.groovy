// Seed job (run by Configuration-as-Code) that creates the Cov/reportcov pipeline.
//
// The pipeline is defined HERE, inline — NOT read from a Jenkinsfile in the repository — so the
// player cannot view or edit it. It polls the reportcov repo over git every minute (an SCM poll, no
// inbound webhook); on a new commit it "notifies the maintainers" by echoing the latest commit
// SUBJECT through a shell. The subject is interpolated straight into the shell command (a Groovy
// GString -> `sh`), exactly the upstream pattern `sh "echo Pull Request ${title} ..."`, so a crafted
// subject executes arbitrary commands. The notify step binds the artifact server's SSH key as $KEY,
// so the injected command runs with the deploy key in its environment. That is the foothold: an
// attacker with write access to reportcov steals $KEY here (CICD-SEC-8: this pipeline is the
// ungoverned trust boundary into the shared artifact service).
pipelineJob('cov-reportcov') {
    displayName('Cov » reportcov (notify)')
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
                git branch: 'main', url: 'http://gitea:3000/Cov/reportcov.git', credentialsId: 'gitea-jenkins'
            }
        }
        stage('Notify maintainers') {
            steps {
                withCredentials([string(credentialsId: 'artifact-key', variable: 'KEY')]) {
                    script {
                        sh 'git log -1 --pretty=%s > .commit-subject'
                        def title = readFile('.commit-subject').trim()
                        sh "echo New change in Cov/reportcov: ${title} - notifying the Cov maintainers"
                    }
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
