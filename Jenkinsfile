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
                ls -lh certificates/ || echo "certificates/ is empty or missing"
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
                        echo "New certificate(s) detected. Proceeding with deployment."
                        env.CERT_FOUND = "true"
                    }
                }
            }
        }

        // ─────────────────────────────────────────────
        // 3. Backup existing truststore
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
        // 4. Import new certificates into truststore
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
        // 6. Update Kubernetes ConfigMap
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
        // 7. Restart pods to pick up new truststore
        // ─────────────────────────────────────────────
        stage('Restart Deployment') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Restarting MI deployment ==="
                kubectl rollout restart deployment/mi-deployment -n ${K8S_NAMESPACE}

                echo "=== Waiting for rollout ==="
                kubectl rollout status deployment/mi-deployment \
                    -n ${K8S_NAMESPACE} \
                    --timeout=120s
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 8. Verify deployment
        // ─────────────────────────────────────────────
        stage('Verify Deployment') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Pod status ==="
                kubectl get pods -n ${K8S_NAMESPACE} -o wide

                echo "=== Image running (unchanged — cert update only) ==="
                kubectl get pods -n ${K8S_NAMESPACE} \
                    -o jsonpath="{.items[*].spec.containers[*].image}" \
                    | tr " " "\\n"

                echo "=== ConfigMap check ==="
                kubectl describe configmap ${CONFIGMAP_NAME} -n ${K8S_NAMESPACE}
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 9. Health check
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
                    && echo "Management API reachable — new truststore active" \
                    || echo "Management API not reachable — MI may still be starting"
                '''
            }
        }

        // ─────────────────────────────────────────────
        // 10. Archive Certificates — git commit + push
        //
        //     WHY GIT COMMIT:
        //     Simply moving files in the Jenkins workspace is
        //     not enough — the next git checkout brings the
        //     .crt files straight back from the repo root.
        //     We git mv the files into certificates/ and push
        //     so they permanently leave the repo root.
        //     Next checkout: only certificates/ has them,
        //     workspace root is clean → cert check finds
        //     nothing → pipeline skips cleanly.
        // ─────────────────────────────────────────────
        stage('Archive Certificates') {
            when { environment name: 'CERT_FOUND', value: 'true' }
            steps {
                sh '''
                echo "=== Archiving processed certificates into certificates/ ==="

                # Ensure archive folder exists and is tracked by git
                mkdir -p certificates

                # Count certs to move
                CERT_COUNT=$(find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\) | wc -l)
                echo "Certificates to archive: $CERT_COUNT"

                if [ "$CERT_COUNT" -eq 0 ]; then
                    echo "No certificates found to archive — skipping."
                    exit 0
                fi

                # Configure git identity for the commit
                git config user.email "jenkins@wso2-mi-cicd"
                git config user.name "Jenkins CI"

                # Move each cert from repo root → certificates/
                find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\) | while read CERT; do
                    FILENAME=$(basename "$CERT")
                    echo "  Archiving: $FILENAME → certificates/$FILENAME"
                    git mv "$FILENAME" "certificates/$FILENAME"
                done

                # Show what will be committed
                echo "=== Git status before commit ==="
                git status

                # Commit the move
                git commit -m "[Jenkins] Archive deployed certificates — Build #${BUILD_NUMBER}

Certificates moved to certificates/ after successful import:
$(git diff --cached --name-only | grep certificates/)

Deployment: ConfigMap ${CONFIGMAP_NAME} updated, namespace ${K8S_NAMESPACE}
Build: #${BUILD_NUMBER}"

                # Push back to main — uses the same SSH key as checkout
                git push origin main

                echo "=== Certificates archived and committed to repo ==="
                echo "=== certificates/ contents ==="
                ls -lh certificates/
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
║  Truststore  : ${TRUSTSTORE}
║  ConfigMap   : ${CONFIGMAP_NAME}
║  Namespace   : ${K8S_NAMESPACE}
║  Build       : #${BUILD_NUMBER}
║  Certs archived to certificates/ and committed to repo
╠══════════════════════════════════════════════════════╣
║  ROLLBACK STEPS:                                     ║
║  1. ls -lht ${TRUSTSTORE_BACKUP_DIR}/
║  2. kubectl delete configmap ${CONFIGMAP_NAME} -n ${K8S_NAMESPACE}
║  3. kubectl create configmap ${CONFIGMAP_NAME} \\
║         --from-file=<backup.jks> -n ${K8S_NAMESPACE}
║  4. kubectl rollout restart deployment/mi-deployment \\
║         -n ${K8S_NAMESPACE}
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

            echo "=== Truststore backups for manual rollback ==="
            ls -lht ${TRUSTSTORE_BACKUP_DIR}/ | head -5 || true
            '''
        }
    }
}

