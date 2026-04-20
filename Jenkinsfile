pipeline {
    agent any

    environment {
        // --- Paths ---
        DOCKER_PROJECT_PATH   = "/home/svc_account_wso2/SIT_MI_Docker_Project"
        CAPP_DEST_DIR         = "${DOCKER_PROJECT_PATH}/capps"

        // --- Truststore ---
        TRUSTSTORE            = "client-truststore.jks"
        TRUSTSTORE_PASS       = "wso2carbon"
        TRUSTSTORE_BACKUP_DIR = "${DOCKER_PROJECT_PATH}/truststore-backups"

        // --- Docker (mirrors CApp pipeline exactly) ---
        IMAGE_NAME            = "mi-sit"

        // --- Kind cluster ---
        KIND_CLUSTER          = "wso2-cluster"

        // --- Kubernetes ---
        K8S_NAMESPACE         = "mi"
        CONFIGMAP_NAME        = "mi-truststore-config"
        HELM_RELEASE          = "mi"
        HELM_CHART_PATH       = "${DOCKER_PROJECT_PATH}/helm"
        VALUES_FILE           = "${DOCKER_PROJECT_PATH}/values-dev.yaml"
    }

    stages {

        // ─────────────────────────────────────────────
        // 1. Checkout
        // ─────────────────────────────────────────────
        stage('Checkout Code') {
            steps {
                git branch: 'main',
                    credentialsId: 'github-ssh-key',
                    url: 'git@github.com:pradyuman202-max/mi-cert-deployment.git'
            }
        }

        stage('Verify Repo Files') {
            steps {
                sh '''
                echo "=== Workspace root ==="
                ls -l

                echo "=== Scripts ==="
                ls -l scripts/

                echo "=== Certificate files in workspace root ==="
                find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\) || echo "None found"

                echo "=== Already archived certificates ==="
                ls -lh certificates/ 2>/dev/null || echo "certificates/ is empty or missing"

                echo "=== CApps available in build context ==="
                ls -lh ${CAPP_DEST_DIR}/ || echo "WARNING: capps/ is empty or missing"

                echo "=== Current image tag in values-dev.yaml ==="
                grep "tag:" ${VALUES_FILE} || echo "WARNING: could not read tag"
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 2. Certificate check — alias-based detection
        //    Runs ONCE. Sets CERT_FOUND flag.
        // ─────────────────────────────────────────────
        stage('Certificate Check') {
            steps {
                script {
                    def certCheck = sh(
                        script: """
                        chmod +x scripts/this_cert_check.sh
                        scripts/this_cert_check.sh \
                            ${DOCKER_PROJECT_PATH}/${TRUSTSTORE} \
                            ${TRUSTSTORE_PASS}
                        """,
                        returnStatus: true
                    )

                    if (certCheck != 0) {
                        echo "No new certificates detected. All downstream stages will be skipped."
                        currentBuild.description = "Skipped — no new certificate"
                        env.CERT_FOUND = "false"
                    } else {
                        echo "New certificate(s) detected. Proceeding with full deployment."
                        env.CERT_FOUND = "true"
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 3. Resolve next image tag
        //
        //    TAG COLLISION FIX:
        //    Reads current tag from values-dev.yaml and
        //    increments by +1. Then checks if that new
        //    tag ALREADY EXISTS locally (from a previous
        //    failed build). If it does → deletes it first
        //    so docker build starts clean every time.
        //
        //    This prevents the scenario:
        //    Build N  → builds sit0018 → helm fails
        //               → values-dev.yaml still sit0017
        //    Build N+1 → resolves sit0018 again
        //               → sit0018 exists locally → ERROR
        //    Fix: detect and remove stale sit0018 before
        //    building fresh.
        // ─────────────────────────────────────────────
        stage('Resolve Image Tag') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                script {
                    def currentTag = sh(
                        script: "grep 'tag:' ${VALUES_FILE} | sed 's/.*tag: *//' | tr -d ' '",
                        returnStdout: true
                    ).trim()

                    echo "Current tag in values-dev.yaml: ${currentTag}"

                    def currentNum = currentTag.replaceAll(/[^0-9]/, '').toInteger()
                    def nextNum    = currentNum + 1
                    def nextTag    = String.format("sit%04d", nextNum)

                    env.IMAGE_TAG  = nextTag
                    env.FULL_IMAGE = "${env.IMAGE_NAME}:${nextTag}"

                    echo "Resolved new image tag: ${env.FULL_IMAGE}"
                    currentBuild.description = "Cert update — ${env.FULL_IMAGE}"

                    // ── TAG COLLISION CHECK ──────────────────────────
                    // If this exact tag already exists locally, it means
                    // a previous build created it but failed before
                    // updating values-dev.yaml. Remove the stale image
                    // so we always build fresh with a clean layer cache.
                    def tagExists = sh(
                        script: "docker images ${env.IMAGE_NAME} --format '{{.Tag}}' | grep -x '${nextTag}' || true",
                        returnStdout: true
                    ).trim()

                    if (tagExists) {
                        echo "WARNING: Tag ${env.FULL_IMAGE} already exists locally from a previous failed build."
                        echo "Removing stale image before rebuilding..."
                        sh "docker rmi ${env.FULL_IMAGE} || true"
                        echo "Stale image removed. Will build fresh."
                    } else {
                        echo "Tag ${env.FULL_IMAGE} is clean — no collision detected."
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 4. Backup existing truststore
        // ─────────────────────────────────────────────
        stage('Backup Truststore') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Backing up existing truststore before update ==="
                mkdir -p ${TRUSTSTORE_BACKUP_DIR}

                TRUSTSTORE_PATH="${DOCKER_PROJECT_PATH}/${TRUSTSTORE}"
                BACKUP_FILE="${TRUSTSTORE_BACKUP_DIR}/client-truststore_$(date +%Y%m%d_%H%M%S).jks"

                if [ -f "$TRUSTSTORE_PATH" ]; then
                    cp "$TRUSTSTORE_PATH" "$BACKUP_FILE"
                    echo "Backup saved: $BACKUP_FILE"
                    echo "=== Existing backups (latest first) ==="
                    ls -lht ${TRUSTSTORE_BACKUP_DIR}/ | head -10
                else
                    echo "No existing truststore found — skipping backup."
                fi
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 5. Import new certificates into truststore
        // ─────────────────────────────────────────────
        stage('Import Certificates') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Starting certificate import ==="
                chmod +x scripts/import-cert.sh

                TRUSTSTORE_PATH="${DOCKER_PROJECT_PATH}/${TRUSTSTORE}"

                if [ ! -f "$TRUSTSTORE_PATH" ]; then
                    echo "Truststore not found — creating a fresh one..."
                    keytool -genkeypair \
                        -alias temp \
                        -keystore "$TRUSTSTORE_PATH" \
                        -storepass ${TRUSTSTORE_PASS} \
                        -keypass  ${TRUSTSTORE_PASS} \
                        -dname "CN=temp" \
                        -keyalg RSA
                    keytool -delete \
                        -alias temp \
                        -keystore "$TRUSTSTORE_PATH" \
                        -storepass ${TRUSTSTORE_PASS}
                    echo "Empty truststore created."
                fi

                find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\) | while read CERT; do
                    ALIAS=$(basename "$CERT" | cut -d. -f1)
                    echo "--- Importing: $CERT  →  alias: $ALIAS ---"
                    ./scripts/import-cert.sh "$CERT" "$TRUSTSTORE_PATH" "${TRUSTSTORE_PASS}" "$ALIAS"
                done

                echo "=== All certificates imported successfully ==="
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 6. Verify truststore contents
        // ─────────────────────────────────────────────
        stage('Verify Truststore') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Truststore contents after import ==="
                keytool -list \
                    -keystore "${DOCKER_PROJECT_PATH}/${TRUSTSTORE}" \
                    -storepass ${TRUSTSTORE_PASS}
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 7. Docker Build — new image with updated
        //    truststore baked in (mirrors CApp pipeline)
        // ─────────────────────────────────────────────
        stage('Docker Build') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Pre-build context check ==="

                # Truststore check
                if [ ! -f "${DOCKER_PROJECT_PATH}/${TRUSTSTORE}" ]; then
                    echo "ERROR: Truststore not found at ${DOCKER_PROJECT_PATH}/${TRUSTSTORE}"
                    exit 1
                fi
                echo "Truststore : OK — $(ls -lh ${DOCKER_PROJECT_PATH}/${TRUSTSTORE})"

                # CApp check — Dockerfile has COPY capps/*.car so capps/ must not be empty
                CAR_COUNT=$(find ${CAPP_DEST_DIR} -name "*.car" -type f 2>/dev/null | wc -l)
                if [ "$CAR_COUNT" -eq 0 ]; then
                    echo "ERROR: No .car files found in ${CAPP_DEST_DIR}/"
                    echo "       Run the CApp pipeline at least once before the cert pipeline."
                    exit 1
                fi
                echo "CApps      : OK — ${CAR_COUNT} .car file(s) in capps/"

                echo "=== Building Docker image: ${FULL_IMAGE} ==="
                cd ${DOCKER_PROJECT_PATH}
                docker build \
                    --no-cache \
                    -t ${FULL_IMAGE} \
                    .

                echo "=== Image built successfully ==="
                docker images | grep ${IMAGE_NAME}
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 8. Load image into Kind (mirrors CApp pipeline)
        // ─────────────────────────────────────────────
        stage('Load Image into Kind') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Loading ${FULL_IMAGE} into kind cluster: ${KIND_CLUSTER} ==="
                kind load docker-image ${FULL_IMAGE} --name ${KIND_CLUSTER}

                echo "=== All mi-sit images in kind ==="
                docker exec ${KIND_CLUSTER}-control-plane crictl images | grep ${IMAGE_NAME}
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 9. Update values-dev.yaml with new tag
        //    Done AFTER successful docker build + kind
        //    load so that if build fails, values-dev.yaml
        //    still holds the last GOOD tag for next run.
        // ─────────────────────────────────────────────
        stage('Update values-dev.yaml') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Updating image section in values-dev.yaml ==="

                sed -i "s|repository:.*|repository: ${IMAGE_NAME}|"  ${VALUES_FILE}
                sed -i "s|tag:.*|tag: ${IMAGE_TAG}|"                 ${VALUES_FILE}
                sed -i "s|pullPolicy:.*|pullPolicy: IfNotPresent|"   ${VALUES_FILE}

                echo "=== Current image section in values-dev.yaml ==="
                grep -A 3 "^image:" ${VALUES_FILE}
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 10. Update Kubernetes ConfigMap
        // ─────────────────────────────────────────────
        stage('Update Kubernetes ConfigMap') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Updating ConfigMap: ${CONFIGMAP_NAME}  namespace: ${K8S_NAMESPACE} ==="

                kubectl delete configmap ${CONFIGMAP_NAME} \
                    -n ${K8S_NAMESPACE} \
                    --ignore-not-found

                kubectl create configmap ${CONFIGMAP_NAME} \
                    --from-file=${DOCKER_PROJECT_PATH}/${TRUSTSTORE} \
                    -n ${K8S_NAMESPACE}

                echo "=== ConfigMap updated ==="
                kubectl describe configmap ${CONFIGMAP_NAME} -n ${K8S_NAMESPACE}
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 11. Helm deploy + rollout (mirrors CApp pipeline)
        // ─────────────────────────────────────────────
        stage('Helm Deploy') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Deploying to namespace: ${K8S_NAMESPACE} ==="
                helm upgrade --install ${HELM_RELEASE} ${HELM_CHART_PATH} \
                    -f ${VALUES_FILE} \
                    -n ${K8S_NAMESPACE} \
                    --timeout 3m0s

                echo "=== Forcing pod restart to use new image + truststore ==="
                kubectl rollout restart deployment/mi-deployment -n ${K8S_NAMESPACE}

                echo "=== Waiting for rollout ==="
                kubectl rollout status deployment/mi-deployment \
                    -n ${K8S_NAMESPACE} \
                    --timeout=120s

                helm status ${HELM_RELEASE} -n ${K8S_NAMESPACE}
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 12. Verify deployment (mirrors CApp pipeline)
        // ─────────────────────────────────────────────
        stage('Verify Deployment') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Pod status ==="
                kubectl get pods -n ${K8S_NAMESPACE} -o wide

                echo "=== Image running in pods ==="
                kubectl get pods -n ${K8S_NAMESPACE} \
                    -o jsonpath="{.items[*].spec.containers[*].image}" \
                    | tr " " "\\n"

                echo "=== ConfigMap check ==="
                kubectl describe configmap ${CONFIGMAP_NAME} -n ${K8S_NAMESPACE}
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 13. Health check (mirrors CApp pipeline)
        // ─────────────────────────────────────────────
        stage('Health Check') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Waiting 15s for MI to initialize ==="
                sleep 15

                POD=$(kubectl get pods -n ${K8S_NAMESPACE} \
                    -l app=mi \
                    --field-selector=status.phase=Running \
                    -o jsonpath="{.items[0].metadata.name}")

                echo "=== Checking pod: $POD ==="
                kubectl exec $POD -n ${K8S_NAMESPACE} -- \
                    curl -sf http://localhost:9164/management/apis \
                    -H "Authorization: Basic YWRtaW46YWRtaW4=" \
                    && echo "Management API reachable — image + truststore confirmed" \
                    || echo "Management API not reachable — MI may still be starting"
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 14. Archive Certificates — git mv + commit
        //
        //     Moves .crt/.cer files from repo root into
        //     certificates/ AND commits+pushes to GitHub.
        //     This permanently removes them from repo root
        //     so next checkout never brings them back.
        //     Next run: workspace root is clean →
        //     cert check finds nothing → pipeline skips.
        // ─────────────────────────────────────────────
        stage('Archive Certificates') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Archiving processed certificates into certificates/ ==="
                mkdir -p certificates

                CERT_COUNT=$(find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\) | wc -l)
                echo "Certificates to archive: $CERT_COUNT"

                if [ "$CERT_COUNT" -eq 0 ]; then
                    echo "No certificates found to archive — skipping."
                    exit 0
                fi

                git config user.email "jenkins@wso2-mi-cicd"
                git config user.name "Jenkins CI"

                find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\) | while read CERT; do
                    FILENAME=$(basename "$CERT")
                    echo "  Archiving: $FILENAME → certificates/$FILENAME"
                    git mv "$FILENAME" "certificates/$FILENAME"
                done

                echo "=== Git status before commit ==="
                git status

                git commit -m "[Jenkins] Archive deployed certificates — Build #${BUILD_NUMBER}

Certificates moved to certificates/ after successful deployment.
Image deployed: ${FULL_IMAGE}
Namespace: ${K8S_NAMESPACE}
Build: #${BUILD_NUMBER}"

                git push origin main

                echo "=== Certificates committed and pushed to repo ==="
                ls -lh certificates/
                '''
            }
        }
    }

    // ─────────────────────────────────────────────
    // Post actions (mirrors CApp pipeline)
    // ─────────────────────────────────────────────
    post {
        success {
            script {
                if (env.CERT_FOUND == 'true') {
                    echo """
╔══════════════════════════════════════════════════════╗
║        Certificate Deployment SUCCESS                ║
╠══════════════════════════════════════════════════════╣
║  Image       : ${env.FULL_IMAGE}
║  Truststore  : ${TRUSTSTORE}
║  ConfigMap   : ${CONFIGMAP_NAME}
║  Namespace   : ${K8S_NAMESPACE}
║  Build       : #${BUILD_NUMBER}
║  Certs archived and committed to repo
╠══════════════════════════════════════════════════════╣
║  ROLLBACK STEPS:                                     ║
║                                                      ║
║  -- Image rollback --                                ║
║  1. sed -i "s|tag:.*|tag: sit####|" ${VALUES_FILE}
║  2. helm upgrade mi ${HELM_CHART_PATH} \\
║        -f ${VALUES_FILE} -n ${K8S_NAMESPACE}
║  3. kubectl rollout restart deployment/mi-deployment \\
║        -n ${K8S_NAMESPACE}
║                                                      ║
║  -- Truststore rollback --                           ║
║  1. ls -lht ${TRUSTSTORE_BACKUP_DIR}/
║  2. kubectl delete configmap ${CONFIGMAP_NAME} \\
║        -n ${K8S_NAMESPACE}
║  3. kubectl create configmap ${CONFIGMAP_NAME} \\
║        --from-file=<backup.jks> -n ${K8S_NAMESPACE}
║  4. kubectl rollout restart deployment/mi-deployment \\
║        -n ${K8S_NAMESPACE}
╚══════════════════════════════════════════════════════╝
                    """
                } else {
                    echo "Pipeline completed — no new certificates detected, all stages skipped cleanly."
                }
            }
        }
        failure {
            sh '''
            echo "=== FAILURE DIAGNOSTICS ==="
            kubectl get pods -n ${K8S_NAMESPACE} || true
            kubectl describe pods -n ${K8S_NAMESPACE} -l app=mi | tail -40 || true

            echo "=== Helm status ==="
            helm status ${HELM_RELEASE} -n ${K8S_NAMESPACE} || true

            echo "=== Truststore backups for manual rollback ==="
            ls -lht ${TRUSTSTORE_BACKUP_DIR}/ | head -5 || true

            echo "=== NOTE: values-dev.yaml was only updated AFTER successful docker build ==="
            echo "=== If build failed before that stage, tag is still the previous good tag ==="
            grep "tag:" ${VALUES_FILE} || true
            '''
        }
        cleanup {
            sh '''
            echo "=== Pruning old local images (keep last 3) ==="
            docker images ${IMAGE_NAME} \
                --format "{{.Tag}}" \
                | grep "^sit" \
                | sort -t t -k2 -n \
                | head -n -3 \
                | xargs -I{} docker rmi ${IMAGE_NAME}:{} || true
            '''
        }
    }
}

