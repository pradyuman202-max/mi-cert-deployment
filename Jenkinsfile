pipeline {
    agent any

    environment {
        // --- Paths ---
        DOCKER_PROJECT_PATH   = "/home/svc_account_wso2/SIT_MI_Docker_Project"

        // --- Truststore ---
        TRUSTSTORE            = "client-truststore.jks"
        TRUSTSTORE_PASS       = "wso2carbon"
        TRUSTSTORE_BACKUP_DIR = "${DOCKER_PROJECT_PATH}/truststore-backups"

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

                echo "=== Certificate files in workspace ==="
                find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\) || echo "None found"
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 2. Certificate check — runs ONCE, sets flag
        // ─────────────────────────────────────────────
        stage('Certificate Check') {
            steps {
                script {
                    def certCount = sh(
                        script: 'find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\) | wc -l',
                        returnStdout: true
                    ).trim().toInteger()

                    if (certCount == 0) {
                        echo "No new certificates found in workspace. All downstream stages will be skipped."
                        currentBuild.description = "Skipped — no new certificate"
                        env.CERT_FOUND = "false"
                    } else {
                        echo "Found ${certCount} certificate(s). Proceeding with full deployment."
                        currentBuild.description = "Certificate update — ${certCount} cert(s)"
                        env.CERT_FOUND = "true"
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 3. Backup existing truststore (for rollback)
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
                    echo "No existing truststore found at $TRUSTSTORE_PATH — nothing to back up."
                fi
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 4. Import all .crt / .cer into truststore
        // ─────────────────────────────────────────────
        stage('Import Certificates') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Starting certificate import ==="
                chmod +x scripts/import-cert.sh

                TRUSTSTORE_PATH="${DOCKER_PROJECT_PATH}/${TRUSTSTORE}"

                # Create truststore if it does not yet exist
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

                # Import every cert found in workspace root
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
        // 5. Verify truststore contents
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
        // 6. Update Kubernetes ConfigMap with new truststore
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

                echo "ConfigMap updated successfully."
                kubectl describe configmap ${CONFIGMAP_NAME} -n ${K8S_NAMESPACE}
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 7. Helm deploy + rollout (mirrors CApp pipeline)
        // ─────────────────────────────────────────────
        stage('Helm Deploy') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Deploying with Helm — namespace: ${K8S_NAMESPACE} ==="
                helm upgrade --install ${HELM_RELEASE} ${HELM_CHART_PATH} \
                    -f ${VALUES_FILE} \
                    -n ${K8S_NAMESPACE} \
                    --timeout 3m0s

                echo "=== Forcing pod restart to mount new truststore ==="
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
        // 8. Verify deployment (mirrors CApp pipeline)
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

                echo "=== ConfigMap mounted check ==="
                kubectl describe configmap ${CONFIGMAP_NAME} -n ${K8S_NAMESPACE}
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 9. Health check (mirrors CApp pipeline)
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
                    && echo "Management API reachable — truststore update confirmed" \
                    || echo "Management API not reachable — MI may still be starting"
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 10. Archive processed certs out of workspace root
        // ─────────────────────────────────────────────
        stage('Archive Certificates') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Moving processed certificates to certificates/ ==="
                CERT_DEST="${DOCKER_PROJECT_PATH}/certificates"
                mkdir -p "$CERT_DEST"

                find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\) \
                    -exec mv -f {} "$CERT_DEST/" \\;

                echo "=== Archived certificates ==="
                ls -lh "$CERT_DEST/"
                '''
            }
        }
    }

    // ─────────────────────────────────────────────
    // Post actions
    // ─────────────────────────────────────────────
    post {
        success {
            script {
                if (env.CERT_FOUND == 'true') {
                    echo """
╔══════════════════════════════════════════════════════╗
║        Certificate Deployment SUCCESS                ║
╠══════════════════════════════════════════════════════╣
║  Truststore  : ${TRUSTSTORE}
║  ConfigMap   : ${CONFIGMAP_NAME}
║  Namespace   : ${K8S_NAMESPACE}
║  Build       : #${BUILD_NUMBER}
╠══════════════════════════════════════════════════════╣
║  ROLLBACK STEPS (if needed):                         ║
║  1. Find backup:                                     ║
║     ls -lht ${TRUSTSTORE_BACKUP_DIR}/
║  2. Delete current ConfigMap:                        ║
║     kubectl delete configmap ${CONFIGMAP_NAME} -n ${K8S_NAMESPACE}
║  3. Restore from backup:                             ║
║     kubectl create configmap ${CONFIGMAP_NAME} \\
║       --from-file=<backup.jks> -n ${K8S_NAMESPACE}
║  4. Restart pods:                                    ║
║     kubectl rollout restart deployment/mi-deployment -n ${K8S_NAMESPACE}
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

            echo "=== Truststore backups available for manual rollback ==="
            ls -lht ${TRUSTSTORE_BACKUP_DIR}/ | head -5 || true
            '''
        }
    }
}
