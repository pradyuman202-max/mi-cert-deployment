pipeline {
    agent any
    environment {
        // --- Paths ---
        DOCKER_PROJECT_PATH       = "/home/svc_account_wso2/SIT_MI_Docker_Project"
        CAPP_DEST_DIR             = "${DOCKER_PROJECT_PATH}/capps"
        // --- Cert folders ---
        CERT_INCOMING_DIR         = "certificates"
        SERVER_CERT_DEPLOYED_DIR  = "${DOCKER_PROJECT_PATH}/certificates/deployed"
        // --- Truststore ---
        TRUSTSTORE                = "client-truststore.jks"
        TRUSTSTORE_PASS           = "wso2carbon"
        TRUSTSTORE_BACKUP_DIR     = "${DOCKER_PROJECT_PATH}/truststore-backups"
        // --- Docker ---
        IMAGE_NAME                = "mi-sit"
        // --- Kind cluster ---
        KIND_CLUSTER              = "wso2-cluster"
        // --- Kubernetes ---
        K8S_NAMESPACE             = "mi"
        CONFIGMAP_NAME            = "mi-truststore-config"
        HELM_RELEASE              = "mi"
        HELM_CHART_PATH           = "${DOCKER_PROJECT_PATH}/helm"
        VALUES_FILE               = "${DOCKER_PROJECT_PATH}/values-dev.yaml"
        // --- Stable image tracking (borrowed from HelloWorld pipeline) ---
        // Written after every successful deployment.
        // Read by MI-Rollback pipeline to restore last known good image.
        LAST_STABLE_FILE          = "${DOCKER_PROJECT_PATH}/last-stable.txt"
        // --- New cert list written by this_cert_check.sh ---
        // Import stage reads this directly — no second alias lookup needed.
        NEW_CERTS_FILE            = "/tmp/new_certs.txt"
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
                echo "=== certificates/ folder — new certs go here ==="
                ls -lh ${CERT_INCOMING_DIR}/ 2>/dev/null || echo "certificates/ is empty or missing"
                echo "=== Server deployed folder ==="
                ls -lh ${SERVER_CERT_DEPLOYED_DIR}/ 2>/dev/null || echo "${SERVER_CERT_DEPLOYED_DIR}/ is empty or missing"
                echo "=== CApps available ==="
                ls -lh ${CAPP_DEST_DIR}/ || echo "WARNING: capps/ is empty or missing"
                echo "=== Current image tag ==="
                grep "tag:" ${VALUES_FILE} || echo "WARNING: could not read tag"
                echo "=== Last stable image ==="
                cat ${LAST_STABLE_FILE} 2>/dev/null || echo "No last-stable.txt found yet"
                '''
            }
        }
        // ─────────────────────────────────────────────
        // 2. Certificate Check
        //    Runs ONCE. Writes new cert paths to
        //    NEW_CERTS_FILE. Import stage reads that
        //    file directly — no second alias check.
        // ─────────────────────────────────────────────
        stage('Certificate Check') {
            steps {
                script {
                    def certCheck = sh(
                        script: """
                        chmod +x scripts/this_cert_check.sh
                        scripts/this_cert_check.sh \
                            ${DOCKER_PROJECT_PATH}/${TRUSTSTORE} \
                            ${TRUSTSTORE_PASS} \
                            ${NEW_CERTS_FILE}
                        """,
                        returnStatus: true
                    )
                    if (certCheck != 0) {
                        echo "No new certificates found. All downstream stages skipped."
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
                    echo "New image tag: ${env.FULL_IMAGE}"
                    currentBuild.description = "Cert update — ${env.FULL_IMAGE}"
                    def tagExists = sh(
                        script: "docker images ${env.IMAGE_NAME} --format '{{.Tag}}' | grep -x '${nextTag}' || true",
                        returnStdout: true
                    ).trim()
                    if (tagExists) {
                        echo "WARNING: Tag ${env.FULL_IMAGE} exists from previous failed build — removing stale image."
                        sh "docker rmi ${env.FULL_IMAGE} || true"
                    } else {
                        echo "Tag ${env.FULL_IMAGE} is clean — no collision detected."
                    }
                }
            }
        }
        // ─────────────────────────────────────────────
        // 4. Backup truststore BEFORE any change
        // ─────────────────────────────────────────────
        stage('Backup Truststore') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Backing up truststore BEFORE any changes ==="
                mkdir -p ${TRUSTSTORE_BACKUP_DIR}
                TRUSTSTORE_PATH="${DOCKER_PROJECT_PATH}/${TRUSTSTORE}"
                BACKUP_FILE="${TRUSTSTORE_BACKUP_DIR}/client-truststore_$(date +%Y%m%d_%H%M%S).jks"
                if [ -f "$TRUSTSTORE_PATH" ]; then
                    cp "$TRUSTSTORE_PATH" "$BACKUP_FILE"
                    echo "Backup saved: $BACKUP_FILE"
                    ls -lht ${TRUSTSTORE_BACKUP_DIR}/ | head -10
                else
                    echo "No existing truststore — skipping backup (first run)."
                fi
                '''
            }
        }
        // ─────────────────────────────────────────────
        // 5. Import New Certificates
        //
        //    Reads NEW_CERTS_FILE written by
        //    this_cert_check.sh — no second alias
        //    lookup. One check total across the pipeline.
        // ─────────────────────────────────────────────
        stage('Import New Certificates') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Importing NEW certificates (list from Certificate Check stage) ==="
                chmod +x scripts/import-cert.sh
                TRUSTSTORE_PATH="${DOCKER_PROJECT_PATH}/${TRUSTSTORE}"

                if [ ! -f "$TRUSTSTORE_PATH" ]; then
                    echo "Truststore not found — creating fresh empty one..."
                    keytool -genkeypair \
                        -alias temp \
                        -keystore "$TRUSTSTORE_PATH" \
                        -storepass ${TRUSTSTORE_PASS} \
                        -keypass   ${TRUSTSTORE_PASS} \
                        -dname "CN=temp" \
                        -keyalg RSA
                    keytool -delete \
                        -alias temp \
                        -keystore "$TRUSTSTORE_PATH" \
                        -storepass ${TRUSTSTORE_PASS}
                    echo "Empty truststore created."
                fi

                # Read the cert list written by this_cert_check.sh.
                # No per-cert alias re-check needed — check already done above.
                while IFS= read -r CERT; do
                    ALIAS=$(basename "$CERT" | cut -d. -f1)
                    echo "IMPORT : $CERT  (alias '$ALIAS')"
                    ./scripts/import-cert.sh "$CERT" "$TRUSTSTORE_PATH" "${TRUSTSTORE_PASS}" "$ALIAS"
                done < "${NEW_CERTS_FILE}"

                echo ""
                echo "=== Truststore entry count after import ==="
                keytool -list \
                    -keystore "$TRUSTSTORE_PATH" \
                    -storepass ${TRUSTSTORE_PASS} \
                    | grep "Your keystore contains"
                '''
            }
        }
        // ─────────────────────────────────────────────
        // 6. Verify Truststore
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
        //     Atomic apply — no delete+create gap.
        // ─────────────────────────────────────────────
        stage('Update Kubernetes ConfigMap') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Updating ConfigMap: ${CONFIGMAP_NAME}  namespace: ${K8S_NAMESPACE} ==="
                kubectl create configmap ${CONFIGMAP_NAME} \
                    --from-file=${DOCKER_PROJECT_PATH}/${TRUSTSTORE} \
                    -n ${K8S_NAMESPACE} \
                    --dry-run=client -o yaml \
                    | kubectl apply -f -
                echo "=== ConfigMap updated ==="
                kubectl describe configmap ${CONFIGMAP_NAME} -n ${K8S_NAMESPACE}
                '''
            }
        }
        // ─────────────────────────────────────────────
        // 11. Helm Deploy + rollout
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
        // 12. Verify Deployment
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
        // 13. Health Check
        // ─────────────────────────────────────────────
        stage('Health Check') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Waiting for pod to be Ready ==="
                kubectl wait --for=condition=Ready pod \
                    -l app=mi \
                    -n ${K8S_NAMESPACE} \
                    --timeout=120s

                POD=$(kubectl get pods -n ${K8S_NAMESPACE} \
                    -l app=mi \
                    --field-selector=status.phase=Running \
                    --sort-by=.metadata.creationTimestamp \
                    -o jsonpath="{.items[-1:].metadata.name}")
                echo "=== Checking pod: $POD ==="

                echo "=== Verifying truststore is mounted correctly ==="
                kubectl exec $POD -n ${K8S_NAMESPACE} -- \
                    ls -lh /home/wso2carbon/client-truststore.jks \
                    && echo "Truststore mount confirmed." \
                    || { echo "ERROR: Truststore not found in pod — mount failed."; exit 1; }

                echo "=== Verifying truststore entry count ==="
                kubectl exec $POD -n ${K8S_NAMESPACE} -- \
                    keytool -list \
                    -keystore /home/wso2carbon/client-truststore.jks \
                    -storepass ${TRUSTSTORE_PASS} \
                    | grep "Your keystore contains"

                echo "Health check complete — truststore confirmed in pod."
                '''
            }
        }
        // ─────────────────────────────────────────────
        // 14. Record Stable Image
        //
        //     Borrowed from HelloWorld pipeline.
        //     Written ONLY after full successful deploy
        //     + health check passes.
        //     MI-Rollback pipeline reads this to restore
        //     last known good image.
        //
        //     Format: TAG|TIMESTAMP|BUILD_NUMBER
        // ─────────────────────────────────────────────
        stage('Record Stable Image') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Recording successful deployment as last stable ==="
                TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
                RECORD="${IMAGE_TAG}|${TIMESTAMP}|build-${BUILD_NUMBER}"
                echo "$RECORD" > ${LAST_STABLE_FILE}
                echo "Recorded: $RECORD"
                echo "=== last-stable.txt ==="
                cat ${LAST_STABLE_FILE}
                '''
            }
        }
        // ─────────────────────────────────────────────
        // 15. Move Certs to Deployed Folder
        //
        //     Intentionally the LAST stage.
        //     Certs only leave certificates/ after:
        //       - health check passed
        //       - stable image recorded
        //     This prevents the next pipeline run from
        //     seeing certs as "already imported" when
        //     a previous deployment actually failed.
        // ─────────────────────────────────────────────
        stage('Move Certs to Deployed Folder') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Moving deployed certs to server archive ==="
                echo "=== Location: ${SERVER_CERT_DEPLOYED_DIR} ==="
                mkdir -p ${SERVER_CERT_DEPLOYED_DIR}

                while IFS= read -r CERT; do
                    FILENAME=$(basename "$CERT")
                    mv "$CERT" "${SERVER_CERT_DEPLOYED_DIR}/${FILENAME}"
                    echo "  Moved: $FILENAME → ${SERVER_CERT_DEPLOYED_DIR}/"
                done < "${NEW_CERTS_FILE}"

                echo ""
                echo "=== Server deployed folder contents ==="
                ls -lh ${SERVER_CERT_DEPLOYED_DIR}/
                '''
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
║  Stable      : Recorded in last-stable.txt
╠══════════════════════════════════════════════════════╣
║  ROLLBACK: trigger MI-Rollback pipeline in Jenkins   ║
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
            echo "=== Last stable image ==="
            cat ${LAST_STABLE_FILE} || echo "No last-stable.txt found"
            echo "=== Current tag in values-dev.yaml ==="
            grep "tag:" ${VALUES_FILE} || true
            echo "=== Truststore backups for manual rollback ==="
            ls -lht ${TRUSTSTORE_BACKUP_DIR}/ | head -5 || true
            '''
            script {
                // Auto-trigger rollback pipeline on any deployment failure.
                // Borrowed from HelloWorld pipeline.
                echo "=== Deployment failed — auto-triggering MI-Rollback pipeline ==="
                build job: 'MI-Rollback',
                      parameters: [
                          string(name: 'TRIGGERED_BY',
                                 value: "${env.JOB_NAME} #${env.BUILD_NUMBER} — auto rollback on failure")
                      ],
                      wait: false
            }
        }
        cleanup {
            sh '''
            echo "=== Pruning old local Docker images (keep last 3) ==="
            docker images ${IMAGE_NAME} \
                --format "{{.Tag}}" \
                | grep "^sit" \
                | sort -t t -k2 -n \
                | head -n -3 \
                | xargs -I{} docker rmi ${IMAGE_NAME}:{} || true

            echo "=== Pruning old truststore backups (keep last 10) ==="
            ls -t ${TRUSTSTORE_BACKUP_DIR}/client-truststore_*.jks 2>/dev/null \
                | tail -n +11 \
                | xargs -I{} rm {} || true
            '''
        }
    }
}

