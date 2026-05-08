pipeline {
    agent any

    environment {
        REGISTRY      = "ghcr.io"
        IMAGE_NAME    = "dhanraj2525/my-service"
        IMAGE_TAG     = "${env.BUILD_NUMBER}"
        FULL_IMAGE    = "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        NAMESPACE     = "dev"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                sh '''
                    echo "=============================="
                    echo "Repository cloned successfully"
                    echo "Build Number: ${BUILD_NUMBER}"
                    echo "Image Tag   : ${IMAGE_TAG}"
                    echo "Full Image  : ${FULL_IMAGE}"
                    echo "=============================="
                    ls -la
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    echo "=============================="
                    echo "Building Docker Image"
                    echo "Image: ${FULL_IMAGE}"
                    echo "=============================="
                    docker build -t ${FULL_IMAGE} .
                    echo "Build successful!"
                    docker images | grep dhanraj2525 || true
                '''
            }
        }

        stage('Push to Registry') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'docker-registry',
                    usernameVariable: 'REG_USER',
                    passwordVariable: 'REG_PASS'
                )]) {
                    sh '''
                        echo "=============================="
                        echo "Authenticating with GHCR"
                        echo "=============================="
                        
                        echo $REG_PASS | docker login ghcr.io \
                            -u $REG_USER --password-stdin

                        echo "Pushing image: ${FULL_IMAGE}"
                        docker push ${FULL_IMAGE}

                        echo "Image pushed successfully!"
                        docker logout ghcr.io
                    '''
                }
            }
        }

        stage('Deploy with Helm') {
            steps {
                withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                    sh '''
                        echo "=============================="
                        echo "Deploying service with Helm"
                        echo "=============================="

                        helm repo add stable https://charts.helm.sh/stable || true
                        helm repo update

                        # Deploy/Upgrade using helm with direct image override
                        if helm list -n ${NAMESPACE} | grep -q my-service; then
                            echo "Upgrading existing release..."
                            helm upgrade my-service ./. \
                                --namespace ${NAMESPACE} \
                                --values values.yaml \
                                --set image.tag="${BUILD_NUMBER}"
                        else
                            echo "Creating new release..."
                            helm install my-service ./. \
                                --namespace ${NAMESPACE} \
                                --values values.yaml \
                                --set image.tag="${BUILD_NUMBER}"
                        fi

                        echo "=============================="
                        echo "Deployment completed!"
                        echo "=============================="
                        echo "Deployed image: ${FULL_IMAGE}"
                    '''
                }
            }
        }
    }

    post {
        always {
            cleanWs()
            sh 'docker rmi ${FULL_IMAGE} || true'
            echo "Pipeline execution finished"
        }
        success {
            echo "=========================================="
            echo "✓ BUILD & DEPLOYMENT SUCCESSFUL"
            echo "=========================================="
            echo "Image Tag       : ${IMAGE_TAG}"
            echo "Full Image      : ${FULL_IMAGE}"
            echo "Deployment      : my-service"
        }
        failure {
            echo "=========================================="
            echo "✗ BUILD OR DEPLOYMENT FAILED"
            echo "=========================================="
            echo "Check the logs above for error details"
            echo "Build Number    : ${BUILD_NUMBER}"
            echo "=========================================="
        }
    }
}