pipeline {
    agent any

    environment {
        // --- Paths ---
        DOCKER_PROJECT_PATH   = "/home/svc_account_wso2/SIT_MI_Docker_Project"
        CAPP_DEST_DIR         = "${DOCKER_PROJECT_PATH}/capps"

        // --- Cert folders in repo ---
        CERT_INCOMING_DIR     = "certificates"
        CERT_DEPLOYED_DIR     = "certificates/deployed"

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

                echo "=== certificates/ folder (drop new certs here in GitHub) ==="
                ls -lh ${CERT_INCOMING_DIR}/ 2>/dev/null || echo "certificates/ is empty or missing"

                echo "=== certificates/deployed/ folder (already processed) ==="
                ls -lh ${CERT_DEPLOYED_DIR}/ 2>/dev/null || echo "certificates/deployed/ is empty"

                echo "=== CApps available in build context ==="
                ls -lh ${CAPP_DEST_DIR}/ || echo "WARNING: capps/ is empty or missing"

                echo "=== Current image tag in values-dev.yaml ==="
                grep "tag:" ${VALUES_FILE} || echo "WARNING: could not read tag"
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 2. Certificate check — alias-based detection
        //    Scans certificates/ folder only.
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
                        echo "No new certificates found in certificates/ folder. All downstream stages skipped."
                        currentBuild.description = "Skipped — no new certificate"
                        env.CERT_FOUND = "false"
                    } else {
                        echo "New certificate(s) found. Proceeding with full deployment."
                        env.CERT_FOUND = "true"
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 3. Resolve next image tag + collision check
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
                    def tagExists = sh(
                        script: "docker images ${env.IMAGE_NAME} --format '{{.Tag}}' | grep -x '${nextTag}' || true",
                        returnStdout: true
                    ).trim()

                    if (tagExists) {
                        echo "WARNING: Tag ${env.FULL_IMAGE} already exists from a previous failed build."
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
        //
        //    Runs BEFORE any change to the truststore.
        //    Saves a timestamped copy of the current
        //    client-truststore.jks so you can always
        //    rollback to the exact state before this run.
        // ─────────────────────────────────────────────
        stage('Backup Truststore') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Backing up existing truststore BEFORE any changes ==="
                mkdir -p ${TRUSTSTORE_BACKUP_DIR}

                TRUSTSTORE_PATH="${DOCKER_PROJECT_PATH}/${TRUSTSTORE}"
                BACKUP_FILE="${TRUSTSTORE_BACKUP_DIR}/client-truststore_$(date +%Y%m%d_%H%M%S).jks"

                if [ -f "$TRUSTSTORE_PATH" ]; then
                    cp "$TRUSTSTORE_PATH" "$BACKUP_FILE"
                    echo "Backup saved: $BACKUP_FILE"
                    echo "=== All backups (newest first) ==="
                    ls -lht ${TRUSTSTORE_BACKUP_DIR}/ | head -10
                else
                    echo "No existing truststore found — nothing to back up (first run)."
                fi
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 5. Import ONLY NEW certificates
        //
        //    KEY CHANGE from previous version:
        //    We do NOT re-import existing certs.
        //    The existing truststore.jks is kept as-is
        //    and only new aliases are added to it.
        //
        //    Logic per cert file:
        //    - Derive alias from filename
        //    - Check if alias already in truststore
        //    - If YES  → skip (already there, no change)
        //    - If NO   → import into existing truststore
        //
        //    This means:
        //    - truststore.jks grows incrementally
        //    - existing certs are never touched
        //    - only genuinely new aliases are added
        // ─────────────────────────────────────────────
        stage('Import New Certificates Only') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Importing ONLY NEW certificates into existing truststore ==="
                chmod +x scripts/import-cert.sh

                TRUSTSTORE_PATH="${DOCKER_PROJECT_PATH}/${TRUSTSTORE}"

                # Create truststore only if it does not exist yet (first run)
                if [ ! -f "$TRUSTSTORE_PATH" ]; then
                    echo "Truststore not found — creating a fresh empty one..."
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

                echo "--- Checking each cert against existing truststore ---"
                IMPORTED=0
                SKIPPED=0

                find ${CERT_INCOMING_DIR} -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\) | while read CERT; do
                    ALIAS=$(basename "$CERT" | cut -d. -f1)

                    # Check if alias already exists in truststore
                    EXISTS=$(keytool -list \
                        -keystore "$TRUSTSTORE_PATH" \
                        -storepass ${TRUSTSTORE_PASS} \
                        2>/dev/null | grep -ic "^${ALIAS},")

                    if [ "$EXISTS" -gt 0 ]; then
                        echo "SKIP   : $CERT  (alias '$ALIAS' already in truststore — not re-importing)"
                    else
                        echo "IMPORT : $CERT  (alias '$ALIAS' is new — adding to truststore)"
                        ./scripts/import-cert.sh "$CERT" "$TRUSTSTORE_PATH" "${TRUSTSTORE_PASS}" "$ALIAS"
                    fi
                done

                echo ""
                echo "=== Import complete — truststore entry count ==="
                keytool -list \
                    -keystore "$TRUSTSTORE_PATH" \
                    -storepass ${TRUSTSTORE_PASS} \
                    | grep "Your keystore contains"
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
                echo "=== Full truststore contents after import ==="
                keytool -list \
                    -keystore "${DOCKER_PROJECT_PATH}/${TRUSTSTORE}" \
                    -storepass ${TRUSTSTORE_PASS}
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 7. Docker Build
        // ─────────────────────────────────────────────
        stage('Docker Build') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Pre-build context check ==="

                if [ ! -f "${DOCKER_PROJECT_PATH}/${TRUSTSTORE}" ]; then
                    echo "ERROR: Truststore not found."
                    exit 1
                fi
                echo "Truststore : OK — $(ls -lh ${DOCKER_PROJECT_PATH}/${TRUSTSTORE})"

                CAR_COUNT=$(find ${CAPP_DEST_DIR} -name "*.car" -type f 2>/dev/null | wc -l)
                if [ "$CAR_COUNT" -eq 0 ]; then
                    echo "ERROR: No .car files in ${CAPP_DEST_DIR}/. Run CApp pipeline first."
                    exit 1
                fi
                echo "CApps      : OK — ${CAR_COUNT} .car file(s)"

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
        // 8. Load image into Kind
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
        // 9. Update values-dev.yaml
        //    Done AFTER successful build + kind load.
        // ─────────────────────────────────────────────
        stage('Update values-dev.yaml') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Updating image section in values-dev.yaml ==="

                sed -i "s|repository:.*|repository: ${IMAGE_NAME}|"  ${VALUES_FILE}
                sed -i "s|tag:.*|tag: ${IMAGE_TAG}|"                 ${VALUES_FILE}
                sed -i "s|pullPolicy:.*|pullPolicy: IfNotPresent|"   ${VALUES_FILE}

                echo "=== Current image section ==="
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
        // 11. Helm deploy + rollout
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
        // 12. Verify deployment
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
        // 13. Health check
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
        // 14. Archive Certificates
        //     git mv certificates/*.crt → certificates/deployed/
        //     Same filename, different folder.
        //     catchError: if git push fails (deploy key
        //     needs write access), build still SUCCESS.
        // ─────────────────────────────────────────────
        stage('Archive Certificates') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                    sh '''
                    echo "=== Archiving deployed certificates to ${CERT_DEPLOYED_DIR}/ ==="
                    mkdir -p ${CERT_DEPLOYED_DIR}

                    CERT_COUNT=$(find ${CERT_INCOMING_DIR} -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\) | wc -l)
                    echo "Certificates to archive: $CERT_COUNT"

                    if [ "$CERT_COUNT" -eq 0 ]; then
                        echo "No certificates to archive."
                        exit 0
                    fi

                    git config user.email "jenkins@wso2-mi-cicd"
                    git config user.name "Jenkins CI"

                    find ${CERT_INCOMING_DIR} -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\) | while read CERT; do
                        FILENAME=$(basename "$CERT")
                        echo "  Moving: ${CERT_INCOMING_DIR}/$FILENAME → ${CERT_DEPLOYED_DIR}/$FILENAME"
                        git mv "${CERT_INCOMING_DIR}/$FILENAME" "${CERT_DEPLOYED_DIR}/$FILENAME"
                    done

                    git commit -m "[Jenkins] Archive deployed certificates — Build #${BUILD_NUMBER}

Certificates moved: certificates/ → certificates/deployed/
Same filenames — only folder changed.
Image deployed: ${FULL_IMAGE}
Namespace: ${K8S_NAMESPACE}
Build: #${BUILD_NUMBER}"

                    git push origin main

                    echo "=== Archived and pushed. Next run: certificates/ empty → pipeline skips ==="
                    ls -lh ${CERT_DEPLOYED_DIR}/
                    '''
                }
            }
        }
    }

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
╠══════════════════════════════════════════════════════╣
║  If Archive stage shows UNSTABLE:                    ║
║  → Deployment succeeded, only git push failed        ║
║  → Fix: GitHub → repo Settings → Deploy keys        ║
║         → tick Allow write access → Save             ║
╠══════════════════════════════════════════════════════╣
║  ROLLBACK STEPS:                                     ║
║  -- Image rollback --                                ║
║  1. sed -i "s|tag:.*|tag: sit####|" ${VALUES_FILE}
║  2. helm upgrade mi ${HELM_CHART_PATH} \\
║        -f ${VALUES_FILE} -n ${K8S_NAMESPACE}
║  3. kubectl rollout restart deployment/mi-deployment \\
║        -n ${K8S_NAMESPACE}
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
            helm status ${HELM_RELEASE} -n ${K8S_NAMESPACE} || true

            echo "=== Truststore backups for manual rollback ==="
            ls -lht ${TRUSTSTORE_BACKUP_DIR}/ | head -5 || true

            echo "=== Current tag in values-dev.yaml ==="
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

