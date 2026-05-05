pipeline {
    agent any

    triggers {
        githubPush()
    }

    environment {
        // ── Your actual values ──────────────────────────
        REGISTRY    = "docker.io"
        IMAGE_NAME  = "dhanraj2525/my-service"
        COMMIT_HASH = "${env.GIT_COMMIT[0..7]}"
        FULL_IMAGE  = "${REGISTRY}/${IMAGE_NAME}:${COMMIT_HASH}"
        CHART_PATH  = "charts/my-service"

        // ── Your actual GitHub repos (SSH) ──────────────
        APP_REPO    = "git@github.com:dhanraj2525/my-service.git"
        GITOPS_REPO = "git@github.com:dhanraj2525/k8s-gitops-repo.git"

        // ── Your actual ArgoCD server ───────────────────
        ARGOCD_SERVER = "10.184.34.6:31929"
    }

    stages {

        // ─────────────────────────────────────────────────
        // STAGE 1: Decide which environment to deploy to
        // main or tag → production
        // staging     → staging
        // develop     → dev
        // ─────────────────────────────────────────────────
        stage('Resolve Environment') {
            steps {
                script {
                    def branch = env.GIT_BRANCH ?: ''
                    def tag    = env.TAG_NAME    ?: ''

                    echo "Branch : ${branch}"
                    echo "Tag    : ${tag}"
                    echo "Commit : ${COMMIT_HASH}"

                    def isMain    = branch ==~ /.*main$/
                    def isStaging = branch ==~ /.*staging$/
                    def isDev     = branch ==~ /.*(develop|feature\/.+)$/
                    def isTag     = tag    ==~ /^v\d+\.\d+\.\d+$/

                    if (isTag || isMain) {
                        env.DEPLOY_ENV  = 'production'
                        env.VALUES_FILE = "${CHART_PATH}/values-prod.yaml"
                        env.ARGOCD_APP  = 'my-service-prod'
                        env.TRIGGER     = isTag ? "tag:${tag}" : "branch:main"

                    } else if (isStaging) {
                        env.DEPLOY_ENV  = 'staging'
                        env.VALUES_FILE = "${CHART_PATH}/values-staging.yaml"
                        env.ARGOCD_APP  = 'my-service-staging'
                        env.TRIGGER     = "branch:staging"

                    } else if (isDev) {
                        env.DEPLOY_ENV  = 'dev'
                        env.VALUES_FILE = "${CHART_PATH}/values-dev.yaml"
                        env.ARGOCD_APP  = 'my-service-dev'
                        env.TRIGGER     = "branch:${branch}"

                    } else {
                        echo "Branch '${branch}' has no deploy target. Skipping."
                        currentBuild.result = 'NOT_BUILT'
                        error("Pipeline skipped — no matching environment")
                    }

                    echo "Deploy Env : ${env.DEPLOY_ENV}"
                    echo "Values File: ${env.VALUES_FILE}"
                    echo "ArgoCD App : ${env.ARGOCD_APP}"
                }
            }
        }

        // ─────────────────────────────────────────────────
        // STAGE 2: Build Docker image
        // Tag = commit hash only — never latest
        // ─────────────────────────────────────────────────
        stage('Build Image') {
            steps {
                sh '''
                    docker build \
                        --build-arg COMMIT_HASH=${COMMIT_HASH} \
                        --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                        -t ${FULL_IMAGE} .

                    echo "Built: ${FULL_IMAGE}"
                '''
            }
        }

        // ─────────────────────────────────────────────────
        // STAGE 3: Run tests inside built image
        // ─────────────────────────────────────────────────
        stage('Test') {
            steps {
                sh '''
                    docker run --rm \
                        -e APP_ENV=test \
                        ${FULL_IMAGE} npm test
                '''
            }
        }

        // ─────────────────────────────────────────────────
        // STAGE 4: Push image to DockerHub
        // Uses 'docker-registry' credential from Jenkins
        // ─────────────────────────────────────────────────
        stage('Push Image') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'docker-registry',
                    usernameVariable: 'REG_USER',
                    passwordVariable: 'REG_PASS'
                )]) {
                    sh '''
                        echo $REG_PASS | docker login \
                            -u $REG_USER --password-stdin

                        docker push ${FULL_IMAGE}

                        echo "Pushed: ${FULL_IMAGE}"
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────────
        // STAGE 5: Update image tag in GitOps repo
        // Uses 'github-repo' SSH credential from Jenkins
        // ArgoCD detects this change and auto deploys
        // ─────────────────────────────────────────────────
        stage('Update Helm Values') {
            steps {
                sshagent(credentials: ['github-repo']) {
                    sh '''
                        rm -rf gitops-tmp

                        # Clone your GitOps repo
                        GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" \
                        git clone ${GITOPS_REPO} gitops-tmp

                        cd gitops-tmp

                        # Read current tag
                        OLD_TAG=$(yq e '.image.tag' ${VALUES_FILE})
                        echo "Old tag: ${OLD_TAG}"
                        echo "New tag: ${COMMIT_HASH}"

                        # Update image.tag with new commit hash
                        yq e ".image.tag = \\"${COMMIT_HASH}\\"" -i ${VALUES_FILE}

                        # Show what changed
                        git diff ${VALUES_FILE}

                        # Commit and push
                        git config user.email "jenkins@ci.internal"
                        git config user.name  "Jenkins CI"
                        git add ${VALUES_FILE}
                        git commit -m "ci(${DEPLOY_ENV}): ${OLD_TAG} -> ${COMMIT_HASH} [skip ci]"

                        GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" \
                        git push origin main

                        cd .. && rm -rf gitops-tmp

                        echo "GitOps updated. ArgoCD will now auto-sync."
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────────
        // STAGE 6: Wait for ArgoCD to finish deployment
        // Uses 'argocd-auth-token' credential from Jenkins
        // ─────────────────────────────────────────────────
        stage('Verify Deployment') {
            steps {
                withCredentials([string(
                    credentialsId: 'argocd-auth-token',
                    variable: 'ARGOCD_TOKEN'
                )]) {
                    sh '''
                        echo "Waiting for ArgoCD to sync ${ARGOCD_APP}..."

                        argocd app wait ${ARGOCD_APP} \
                            --auth-token  $ARGOCD_TOKEN \
                            --server      ${ARGOCD_SERVER} \
                            --health \
                            --sync \
                            --timeout 300 \
                            --insecure

                        echo "Deployment verified for: ${ARGOCD_APP}"
                    '''
                }
            }
        }
    }

    post {
        always {
            // Clean up local docker image after every build
            sh 'docker rmi ${FULL_IMAGE} || true'
        }
        success {
            echo "SUCCESS: my-service deployed to ${env.DEPLOY_ENV} with commit ${env.COMMIT_HASH}"
        }
        failure {
            echo "FAILED: my-service deployment failed on ${env.DEPLOY_ENV} with commit ${env.COMMIT_HASH}"
        }
    }
}