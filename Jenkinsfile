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
        // dev branch  → update values-dev.yaml     → deploy DEV
        // main branch → update values-staging.yaml → deploy STAGING
        // tag v*.*.*  → build + push ONLY          → NO deploy
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
                    def isTag  = tag    ==~ /^v\d+\.\d+\.\d+$/

                    if (isDev) {
                        // dev branch → deploy to DEV namespace
                        env.DEPLOY_ENV    = 'dev'
                        env.VALUES_FILE   = "${CHART_PATH}/values-dev.yaml"
                        env.ARGOCD_APP    = 'my-service-dev'
                        env.TRIGGER       = "branch:dev"
                        env.SHOULD_DEPLOY = "true"

                    } else if (isMain) {
                        // main branch → deploy to STAGING namespace
                        env.DEPLOY_ENV    = 'staging'
                        env.VALUES_FILE   = "${CHART_PATH}/values-staging.yaml"
                        env.ARGOCD_APP    = 'my-service-staging'
                        env.TRIGGER       = "branch:main"
                        env.SHOULD_DEPLOY = "true"

                    } else if (isTag) {
                        // tag → build + push image only
                        // image tag will be set in values-prod.yaml manually via ArgoCD
                        env.DEPLOY_ENV    = 'production'
                        env.VALUES_FILE   = "${CHART_PATH}/values-prod.yaml"
                        env.ARGOCD_APP    = 'my-service-prod'
                        env.TRIGGER       = "tag:${tag}"
                        env.SHOULD_DEPLOY = "false"

                    } else {
                        echo "Branch '${branch}' has no deploy target. Skipping."
                        currentBuild.result = 'NOT_BUILT'
                        error("Pipeline skipped — no matching environment")
                    }

                    echo "=============================="
                    echo " Deploy Env   : ${env.DEPLOY_ENV}"
                    echo " Should Deploy: ${env.SHOULD_DEPLOY}"
                    echo " Values File  : ${env.VALUES_FILE}"
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
        // dev branch  → updates values-dev.yaml
        // main branch → updates values-staging.yaml
        // tag         → SKIPPED (manual deploy via ArgoCD)
        //
        // ArgoCD detects the git change and auto deploys
        // ─────────────────────────────────────────────────
        stage('Update Helm Values') {
            when {
                expression { return env.SHOULD_DEPLOY == "true" }
            }
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
                        echo "Old tag : ${OLD_TAG}"
                        echo "New tag : ${COMMIT_HASH}"
                        echo "File    : ${VALUES_FILE}"

                        # Update ONLY image.tag with new commit hash
                        yq e ".image.tag = \\"${COMMIT_HASH}\\"" -i ${VALUES_FILE}

                        # Show what changed
                        echo "--- Git diff ---"
                        git diff ${VALUES_FILE}

                        # Commit and push
                        # [skip ci] prevents Jenkins re-triggering on this commit
                        git config user.email "jenkins@ci.internal"
                        git config user.name  "Jenkins CI"
                        git add ${VALUES_FILE}
                        git commit -m "ci(${DEPLOY_ENV}): ${OLD_TAG} -> ${COMMIT_HASH} [skip ci]"

                        GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no" \
                        git push origin main

                        cd .. && rm -rf gitops-tmp

                        echo "GitOps repo updated."
                        echo "ArgoCD will now auto-sync ${ARGOCD_APP}."
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────────
        // STAGE 6: Wait for ArgoCD to confirm deployment
        //
        // dev branch  → waits for my-service-dev
        // main branch → waits for my-service-staging
        // tag         → SKIPPED
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
                        echo "Running image: ${FULL_IMAGE}"
                    '''
                }
            }
        }
    }

    post {
        always {
            // Always clean up local docker image to save disk space
            sh 'docker rmi ${FULL_IMAGE} || true'
            echo "Pipeline finished"
        }
        success {
            script {
                if (env.SHOULD_DEPLOY == "true") {
                    echo "SUCCESS — Deployed to ${env.DEPLOY_ENV}"
                    echo "Image  : ${env.FULL_IMAGE}"
                    echo "ArgoCD : http://${env.ARGOCD_SERVER}"
                } else {
                    echo "SUCCESS — Tag build complete"
                    echo "Image pushed : ${env.FULL_IMAGE}"
                    echo "To deploy to production:"
                    echo "  1. Go to ArgoCD → http://${env.ARGOCD_SERVER}"
                    echo "  2. Open my-service-prod"
                    echo "  3. Update image.tag to ${env.COMMIT_HASH}"
                    echo "  4. Click Sync"
                }
            }
        }
        failure {
            echo "FAILED — Check the red stage above for error details"
        }
    }
}