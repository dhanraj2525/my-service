pipeline {
    agent any

    environment {
        REGISTRY    = "docker.io"
        IMAGE_NAME  = "dhanraj2525/my-service"
        COMMIT_HASH = "${env.GIT_COMMIT[0..7]}"
        FULL_IMAGE  = "${REGISTRY}/${IMAGE_NAME}:${COMMIT_HASH}"
    }

    stages {

        // ─────────────────────────────────────────────────
        // STAGE 1: Just clone the repo and check files
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
        // ─────────────────────────────────────────────────
        stage('Build Image') {
            steps {
                sh '''
                    echo "Building image: ${FULL_IMAGE}"
                    docker build -t ${FULL_IMAGE} .
                    echo "Build successful"
                    docker images | grep dhanraj2525
                '''
            }
        }

        // ─────────────────────────────────────────────────
        // STAGE 3: Push image to DockerHub
        // ─────────────────────────────────────────────────
        stage('Push Image') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'docker-registry',
                    usernameVariable: 'REG_USER',
                    passwordVariable: 'REG_PASS'
                )]) {
                    sh '''
                        echo "Logging into DockerHub..."
                        echo $REG_PASS | docker login -u $REG_USER --password-stdin

                        echo "Pushing: ${FULL_IMAGE}"
                        docker push ${FULL_IMAGE}

                        echo "Push successful"
                    '''
                }
            }
        }
    }

    post {
        always {
            sh 'docker rmi ${FULL_IMAGE} || true'
            echo "Done"
        }
        success {
            echo "SUCCESS — Image pushed: ${env.FULL_IMAGE}"
        }
        failure {
            echo "FAILED — Check the stage that turned red"
        }
    }
}