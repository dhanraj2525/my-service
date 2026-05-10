pipeline {
    agent any

    environment {

        APP_NAME            = "my-service"
        DOCKER_REGISTRY     = "ghcr.io"
        GITHUB_USERNAME     = "dhanraj2525"
        IMAGE_NAME          = "${DOCKER_REGISTRY}/${GITHUB_USERNAME}/${APP_NAME}"
        IMAGE_TAG           = "${BUILD_NUMBER}"
        GITOPS_REPO         = "git@github.com:dhanraj2525/k8s-gitops-repo.git"
        GITOPS_BRANCH       = "main"
        CHART_PATH          = "my-service"
        GIT_CREDENTIALS_ID  = "github-repo"
        GHCR_CREDENTIALS_ID = "docker-registry"
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
        timestamps()
    }

    stages {

        stage('Checkout Application Repo') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker Image') {
            steps {
                sh """
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                """
            }
        }

        stage('Push Docker Image') {
            steps {

                withCredentials([usernamePassword(
                    credentialsId: "${GHCR_CREDENTIALS_ID}",
                    usernameVariable: 'GH_USER',
                    passwordVariable: 'GH_TOKEN'
                )]) {

                    sh """
                        echo \$GH_TOKEN | docker login ghcr.io -u \$GH_USER --password-stdin

                        docker push ${IMAGE_NAME}:${IMAGE_TAG}

                        docker logout ghcr.io
                    """
                }
            }
        }

        stage('Clone GitOps Repository') {
            steps {

                dir('gitops-repo') {

                    git branch: "${GITOPS_BRANCH}",
                        credentialsId: "${GIT_CREDENTIALS_ID}",
                        url: "${GITOPS_REPO}"
                }
            }
        }

        stage('Update Helm values.yaml') {
            steps {

                dir('gitops-repo') {

                    sh """
                        sed -i 's|tag: .*|tag: "${IMAGE_TAG}"|g' ${CHART_PATH}/values.yaml

                        echo "Updated values.yaml"

                        cat ${CHART_PATH}/values.yaml
                    """
                }
            }
        }

        stage('Commit & Push Changes') {
            steps {

                dir('gitops-repo') {

                    sshagent(credentials: ["${GIT_CREDENTIALS_ID}"]) {

                        sh """
                            git config user.email "jenkins@sarvika.com"
                            git config user.name "jenkins"

                            git add ${CHART_PATH}/values.yaml

                            git commit -m "Update ${APP_NAME} image tag to ${IMAGE_TAG}" || true

                            git push origin ${GITOPS_BRANCH}
                        """
                    }
                }
            }
        }
    }

    post {

        success {
            echo "Pipeline executed successfully"
        }

        failure {
            echo "Pipeline failed"
        }

        always {
            cleanWs()
        }

        cleanup {
            sh 'docker system prune -af || true'
        }
    }
}