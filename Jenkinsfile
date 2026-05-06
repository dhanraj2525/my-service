pipeline {
    agent any

    environment {
        REGISTRY      = "ghcr.io"
        IMAGE_NAME    = "dhanraj2525/my-service"
        COMMIT_HASH   = "${env.GIT_COMMIT[0..7]}"
        FULL_IMAGE    = "${REGISTRY}/${IMAGE_NAME}:${COMMIT_HASH}"
        GITOPS_REPO   = "git@github.com:dhanraj2525/k8s-gitops-repo.git"
        CHART_PATH    = "charts/my-service"
        ARGOCD_SERVER = "10.184.34.6:31929"
    }

    stages {

        // ─────────────────────────────────────────────────
        // STAGE 1: Decide environment based on branch/tag
        //
        // dev branch  → update values-dev.yaml     → ArgoCD auto deploys DEV
        // main branch → update values-staging.yaml → ArgoCD auto deploys STAGING
        // tag *.*.*   → update values-prod.yaml    → ArgoCD waits for manual sync
        // other       → skip pipeline
        // ─────────────────────────────────────────────────
        stage('Resolve Environment') {
            steps {
                script {
                    def branch = env.GIT_BRANCH ?: ''
                    def tag    = env.TAG_NAME    ?: ''

                    echo "=============================="
                    echo " Branch : ${branch}"
                    echo " Tag    : ${tag}"
                    echo " Commit : ${COMMIT_HASH}"
                    echo "=============================="

                    def isMain = branch ==~ /.*main$/
                    def isDev  = branch ==~ /.*dev$/

                    // matches both 1.0.0 and v1.0.0
                    def isTag  = tag    ==~ /^v?\d+\.\d+\.\d+$/

                    if (isDev) {
                        // dev branch → update values-dev.yaml
                        // ArgoCD auto syncs to dev namespace
                        env.DEPLOY_ENV      = 'dev'
                        env.VALUES_FILE     = "${CHART_PATH}/values-dev.yaml"
                        env.ARGOCD_APP      = 'my-service-dev'
                        env.TRIGGER         = "branch:dev"
                        env.SHOULD_DEPLOY   = "true"
                        env.IMAGE_TAG_VALUE = "${COMMIT_HASH}"

                    } else if (isMain) {
                        // main branch → update values-staging.yaml
                        // ArgoCD auto syncs to staging namespace
                        env.DEPLOY_ENV      = 'staging'
                        env.VALUES_FILE     = "${CHART_PATH}/values-staging.yaml"
                        env.ARGOCD_APP      = 'my-service-staging'
                        env.TRIGGER         = "branch:main"
                        env.SHOULD_DEPLOY   = "true"
                        env.IMAGE_TAG_VALUE = "${COMMIT_HASH}"

                    } else if (isTag) {
                        // tag → update values-prod.yaml with tag value
                        // ArgoCD detects change but waits for manual sync
                        env.DEPLOY_ENV      = 'production'
                        env.VALUES_FILE     = "${CHART_PATH}/values-prod.yaml"
                        env.ARGOCD_APP      = 'my-service-prod'
                        env.TRIGGER         = "tag:${tag}"
                        env.SHOULD_DEPLOY   = "false"
                        env.IMAGE_TAG_VALUE = "${COMMIT_HASH}"

                    } else {
                        echo "Branch '${branch}' has no deploy target. Skipping."
                        currentBuild.result = 'NOT_BUILT'
                        error("Pipeline skipped — no matching environment")
                    }

                    echo "=============================="
                    echo " Deploy Env   : ${env.DEPLOY_ENV}"
                    echo " Values File  : ${env.VALUES_FILE}"
                    echo " Image Tag    : ${env.IMAGE_TAG_VALUE}"
                    echo " Auto Deploy  : ${env.SHOULD_DEPLOY}"
                    echo " Trigger      : ${env.TRIGGER}"
                    echo "=============================="
                }
            }
        }

        // ─────────────────────────────────────────────────
        // STAGE 2: Clone repo and verify files
        // ─────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
                sh '''
                    echo "Repo cloned successfully"
                    ls -la
                    echo "Commit hash: ${COMMIT_HASH}"
                '''
            }
        }

        // ─────────────────────────────────────────────────
        // STAGE 3: Build Docker image
        // Runs for ALL branches and tags
        // Tag = commit hash only — never latest
        // ─────────────────────────────────────────────────
        stage('Build Image') {
            steps {
                sh '''
                    echo "Building: ${FULL_IMAGE}"

                    docker build \
                        --build-arg COMMIT_HASH=${COMMIT_HASH} \
                        --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                        -t ${FULL_IMAGE} .

                    echo "Build successful: ${FULL_IMAGE}"
                    docker images | grep dhanraj2525
                '''
            }
        }

        // ─────────────────────────────────────────────────
        // STAGE 4: Push image to GHCR
        // Runs for ALL branches and tags
        // ─────────────────────────────────────────────────
        stage('Push Image') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'docker-registry',
                    usernameVariable: 'REG_USER',
                    passwordVariable: 'REG_PASS'
                )]) {
                    sh '''
                        echo "Logging into GHCR..."
                        echo $REG_PASS | docker login ghcr.io \
                            -u $REG_USER --password-stdin

                        echo "Pushing: ${FULL_IMAGE}"
                        docker push ${FULL_IMAGE}

                        echo "Push successful: ${FULL_IMAGE}"
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────────
        // STAGE 5: Update image.tag in GitOps repo
        //
        // dev branch  → writes commit hash to values-dev.yaml
        // main branch → writes commit hash to values-staging.yaml
        // tag         → writes commit hash to values-prod.yaml
        //
        // ALL three update the file and push to GitOps repo
        // ArgoCD detects the git change automatically
        // ─────────────────────────────────────────────────
        stage('Update Helm Values') {
            steps {
                sshagent(credentials: ['github-repo']) {
                    sh '''
                        rm -rf gitops-tmp

                        echo "Cloning GitOps repo..."
                        GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" \
                        git clone ${GITOPS_REPO} gitops-tmp

                        cd gitops-tmp

                        # Read current tag before update
                        OLD_TAG=$(yq e '.image.tag' ${VALUES_FILE})
                        echo "Old tag    : ${OLD_TAG}"
                        echo "New tag    : ${IMAGE_TAG_VALUE}"
                        echo "Updating   : ${VALUES_FILE}"

                        # Update image.tag with new commit hash
                        yq e ".image.tag = \\"${IMAGE_TAG_VALUE}\\"" -i ${VALUES_FILE}

                        # Show what changed
                        echo "--- Git diff ---"
                        git diff ${VALUES_FILE}

                        # Commit and push to GitOps repo
                        # [skip ci] prevents Jenkins re-triggering on this commit
                        git config user.email "jenkins@ci.internal"
                        git config user.name  "Jenkins CI"
                        git add ${VALUES_FILE}
                        git commit -m "ci(${DEPLOY_ENV}): ${OLD_TAG} -> ${IMAGE_TAG_VALUE} [skip ci]

Trigger : ${TRIGGER}
Image   : ${FULL_IMAGE}
Build   : #${BUILD_NUMBER}"

                        GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" \
                        git push origin main

                        cd .. && rm -rf gitops-tmp

                        echo "GitOps repo updated successfully."
                        echo "File    : ${VALUES_FILE}"
                        echo "New tag : ${IMAGE_TAG_VALUE}"
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────────
        // STAGE 6: Verify ArgoCD deployment
        //
        // dev branch  → waits for my-service-dev sync
        // main branch → waits for my-service-staging sync
        // tag         → SKIPPED (production needs manual sync)
        // ─────────────────────────────────────────────────
        stage('Verify Deployment') {
            when {
                expression { return env.SHOULD_DEPLOY == "true" }
            }
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
                            --timeout     300 \
                            --insecure

                        echo "Deployment verified: ${ARGOCD_APP}"
                        echo "Running image      : ${FULL_IMAGE}"
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
            script {
                if (env.SHOULD_DEPLOY == "true") {
                    echo "SUCCESS — Auto deployed to ${env.DEPLOY_ENV}"
                    echo "Image   : ${env.FULL_IMAGE}"
                    echo "ArgoCD  : http://${env.ARGOCD_SERVER}"
                } else {
                    echo "SUCCESS — values-prod.yaml updated with ${env.IMAGE_TAG_VALUE}"
                    echo "Image pushed  : ${env.FULL_IMAGE}"
                    echo "Next step     : Go to ArgoCD and manually sync my-service-prod"
                    echo "ArgoCD URL    : http://${env.ARGOCD_SERVER}"
                }
            }
        }
        failure {
            echo "FAILED — Check the red stage above for error details"
        }
    }
}