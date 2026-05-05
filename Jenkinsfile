pipeline {
    agent any

    triggers {
        bitbucketPush()
    }

    environment {
        REGISTRY     = "registry.example.com"
        IMAGE_NAME   = "my-org/my-service"
        COMMIT_HASH  = "${env.GIT_COMMIT[0..7]}"
        FULL_IMAGE   = "${REGISTRY}/${IMAGE_NAME}:${COMMIT_HASH}"
        GITOPS_REPO  = "https://bitbucket.org/my-org/k8s-gitops-repo.git"
        CHART_PATH   = "charts/my-service"
    }

    stages {

        // ─────────────────────────────────────────────────────
        // GATE: Map branch/tag → environment
        // ─────────────────────────────────────────────────────
        stage('Resolve Environment') {
            steps {
                script {
                    def branch = env.GIT_BRANCH ?: ''
                    def tag    = env.TAG_NAME    ?: ''

                    echo "Branch : ${branch}"
                    echo "Tag    : ${tag}"
                    echo "Commit : ${COMMIT_HASH}"

                    def isMain    = branch == 'origin/main' || branch == 'main'
                    def isStaging = branch == 'origin/staging' || branch == 'staging'
                    def isDev     = branch.startsWith('origin/develop') ||
                                    branch.startsWith('origin/feature/')
                    def isTag     = tag ==~ /^v\d+\.\d+\.\d+$/

                    if (isTag || isMain) {
                        // ── PRODUCTION ──────────────────────
                        env.DEPLOY_ENV   = 'production'
                        env.VALUES_FILE  = "${CHART_PATH}/values-prod.yaml"
                        env.ARGOCD_APP   = 'my-service-prod'
                        env.K8S_NS       = 'production'
                        env.TRIGGER_TYPE = isTag ? "tag:${tag}" : "branch:main"

                    } else if (isStaging) {
                        // ── STAGING ─────────────────────────
                        env.DEPLOY_ENV   = 'staging'
                        env.VALUES_FILE  = "${CHART_PATH}/values-staging.yaml"
                        env.ARGOCD_APP   = 'my-service-staging'
                        env.K8S_NS       = 'staging'
                        env.TRIGGER_TYPE = "branch:staging"

                    } else if (isDev) {
                        // ── DEV ─────────────────────────────
                        env.DEPLOY_ENV   = 'dev'
                        env.VALUES_FILE  = "${CHART_PATH}/values-dev.yaml"
                        env.ARGOCD_APP   = 'my-service-dev'
                        env.K8S_NS       = 'dev'
                        env.TRIGGER_TYPE = "branch:${branch}"

                    } else {
                        // ── SKIP — unrelated branch ─────────
                        echo "⏭️  Branch '${branch}' has no deployment target."
                        currentBuild.result = 'NOT_BUILT'
                        error("Pipeline skipped — no matching environment")
                    }

                    echo "======================================"
                    echo "  Deploy Env  : ${env.DEPLOY_ENV}"
                    echo "  Values File : ${env.VALUES_FILE}"
                    echo "  ArgoCD App  : ${env.ARGOCD_APP}"
                    echo "  Trigger     : ${env.TRIGGER_TYPE}"
                    echo "======================================"
                }
            }
        }

        // ─────────────────────────────────────────────────────
        // STAGE 1: Build
        // ─────────────────────────────────────────────────────
        stage('Build Docker Image') {
            steps {
                sh '''
                    docker build \
                        --build-arg COMMIT_HASH=${COMMIT_HASH} \
                        --build-arg BUILD_NUMBER=${BUILD_NUMBER} \
                        --build-arg BRANCH=${GIT_BRANCH} \
                        -t ${FULL_IMAGE} \
                        .

                    echo "✅ Built: ${FULL_IMAGE}"
                '''
            }
        }

        // ─────────────────────────────────────────────────────
        // STAGE 2: Test
        // ─────────────────────────────────────────────────────
        stage('Run Tests') {
            steps {
                sh '''
                    docker run --rm \
                        -e APP_ENV=test \
                        ${FULL_IMAGE} \
                        npm test
                '''
            }
        }

        // ─────────────────────────────────────────────────────
        // STAGE 3: Push — commit hash ONLY
        // ─────────────────────────────────────────────────────
        stage('Push Image') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'registry-creds',
                    usernameVariable: 'REG_USER',
                    passwordVariable: 'REG_PASS'
                )]) {
                    sh '''
                        echo $REG_PASS | docker login $REGISTRY \
                            -u $REG_USER --password-stdin

                        docker push ${FULL_IMAGE}

                        echo "✅ Pushed: ${FULL_IMAGE}"
                        echo "🚫 'latest' NOT pushed"
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────────────
        // STAGE 4: Update correct values file in GitOps repo
        // ─────────────────────────────────────────────────────
        stage('Update Helm Values') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'bitbucket-gitops-creds',
                    usernameVariable: 'GIT_USER',
                    passwordVariable: 'GIT_PASS'
                )]) {
                    sh '''
                        rm -rf gitops-tmp
                        git clone https://$GIT_USER:$GIT_PASS@bitbucket.org/my-org/k8s-gitops-repo.git gitops-tmp
                        cd gitops-tmp

                        # Read old tag
                        OLD_TAG=$(yq e '.image.tag' ${VALUES_FILE})
                        echo "Old tag : ${OLD_TAG}"
                        echo "New tag : ${COMMIT_HASH}"
                        echo "File    : ${VALUES_FILE}"

                        # Update ONLY image.tag
                        yq e ".image.tag = \\"${COMMIT_HASH}\\"" -i ${VALUES_FILE}

                        # Show diff
                        echo "--- Diff ---"
                        git diff ${VALUES_FILE}

                        # Commit and push
                        git config user.email "jenkins@ci.internal"
                        git config user.name  "Jenkins CI"
                        git add ${VALUES_FILE}
                        git commit -m "ci(${DEPLOY_ENV}): ${OLD_TAG} → ${COMMIT_HASH} [skip ci]

Service   : my-service
Env       : ${DEPLOY_ENV}
Trigger   : ${TRIGGER_TYPE}
Build     : #${BUILD_NUMBER}
Image     : ${FULL_IMAGE}"

                        git push origin main
                        echo "✅ GitOps updated → ArgoCD syncing ${ARGOCD_APP}"

                        cd ..
                        rm -rf gitops-tmp
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────────────
        // STAGE 5: Wait for ArgoCD sync and verify
        // ─────────────────────────────────────────────────────
        stage('Verify Deployment') {
            steps {
                withCredentials([string(
                    credentialsId: 'argocd-auth-token',
                    variable: 'ARGOCD_TOKEN'
                )]) {
                    sh '''
                        echo "⏳ Waiting for ArgoCD to sync ${ARGOCD_APP}..."

                        argocd app wait ${ARGOCD_APP} \
                            --auth-token $ARGOCD_TOKEN \
                            --server     argocd.example.com \
                            --health \
                            --sync \
                            --timeout    300

                        # Verify running tag
                        RUNNING_TAG=$(argocd app get ${ARGOCD_APP} \
                            --auth-token $ARGOCD_TOKEN \
                            --server argocd.example.com \
                            -o json | jq -r '.status.summary.images[0]' \
                            | cut -d: -f2)

                        echo "Expected : ${COMMIT_HASH}"
                        echo "Running  : ${RUNNING_TAG}"

                        if [ "${RUNNING_TAG}" != "${COMMIT_HASH}" ]; then
                            echo "❌ Tag mismatch!"
                            exit 1
                        fi

                        echo "✅ ${DEPLOY_ENV} running: ${COMMIT_HASH}"
                    '''
                }
            }
        }
    }

    post {
        success {
            slackSend channel: '#deployments', color: 'good',
                message: """
✅ *Deployed Successfully*
- Service : my-service
- Env     : ${env.DEPLOY_ENV}
- Trigger : ${env.TRIGGER_TYPE}
- Commit  : \`${env.COMMIT_HASH}\`
- Image   : \`${env.FULL_IMAGE}\`
- Build   : #${env.BUILD_NUMBER}
                """
        }
        failure {
            slackSend channel: '#deployments', color: 'danger',
                message: """
❌ *Deployment Failed*
- Service : my-service
- Env     : ${env.DEPLOY_ENV}
- Trigger : ${env.TRIGGER_TYPE}
- Commit  : \`${env.COMMIT_HASH}\`
- Build   : #${env.BUILD_NUMBER}
                """
        }
        always {
            sh 'docker rmi ${FULL_IMAGE} || true'
        }
    }
}