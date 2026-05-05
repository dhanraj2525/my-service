pipeline {
    agent any

    environment {
        REGISTRY    = "ghcr.io"
        IMAGE_NAME  = "dhanraj2525/my-service"
        COMMIT_HASH = "${env.GIT_COMMIT[0..7]}"
        FULL_IMAGE  = "${REGISTRY}/${IMAGE_NAME}:${COMMIT_HASH}"
    }

    stages {

        // ─────────────────────────────────────────────────
        // STAGE 1: Clone the repo and check files
        // ─────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
                sh '''
                    echo "Repo cloned successfully"
                    echo "Files in workspace:"
                    ls -la
                    echo "Commit hash: ${COMMIT_HASH}"
                '''
            }
        }

        // ─────────────────────────────────────────────────
        // STAGE 2: Build Docker image
        // Tag = commit hash only — never latest
        // ─────────────────────────────────────────────────
        stage('Build Image') {
            steps {
                sh '''
                    echo "Building image: ${FULL_IMAGE}"
                    docker build \
                        --build-arg COMMIT_HASH=${COMMIT_HASH} \
                        --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                        -t ${FULL_IMAGE} .
                    echo "Build successful"
                    docker images | grep dhanraj2525
                '''
            }
        }

        // ─────────────────────────────────────────────────
        // STAGE 3: Push image to GitHub Container Registry
        // ─────────────────────────────────────────────────
        stage('Push Image') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'docker-registry',
                    usernameVariable: 'REG_USER',
                    passwordVariable: 'REG_PASS'
                )]) {
                    sh '''
                        echo "Logging into GitHub Container Registry..."
                        echo $REG_PASS | docker login ghcr.io \
                            -u $REG_USER --password-stdin

                        echo "Pushing: ${FULL_IMAGE}"
                        docker push ${FULL_IMAGE}

                        echo "Successfully pushed to GHCR"
                        echo "Image: ${FULL_IMAGE}"
                    '''
                }
            }
        }
    }

    post {
        always {
            sh 'docker rmi ${FULL_IMAGE} || true'
            echo "Pipeline finished"
        }
        success {
            echo "SUCCESS — Image available at: ${env.FULL_IMAGE}"
            echo "View at: https://github.com/dhanraj2525?tab=packages"
        }
        failure {
            echo "FAILED — Check the red stage above for error details"
        }
    }
}