pipeline {
    agent any

    environment {
        // Configuration
        TRUSTSTORE = "client-truststore.jks"
        TRUSTSTORE_PASS = "wso2carbon"
        K8S_NAMESPACE = "default" // Change to your namespace
        RELEASE_NAME = "mi-deployment"
        CERT_IMPORTED = "false"
    }

    stages {
        stage('Checkout Code') {
            steps {
                git branch: 'main', 
                    credentialsId: 'github-ssh-key', 
                    url: 'git@github.com:pradyuman202-max/mi-cert-deployment.git'
            }
        }

        stage('Auto Import Certificates') {
            steps {
                script {
                    // We run a shell script that exits with 100 if a change occurred
                    def statusCode = sh(
                        script: '''
                        set +e
                        IMPORT_STATUS=0
                        echo "Searching for new certificates..."
                        
                        # Find all cert files
                        FILES=$(find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\))
                        
                        if [ -z "$FILES" ]; then
                            echo "No certificate files found in root."
                            exit 0
                        fi

                        chmod +x scripts/import-cert.sh

                        for CERT in $FILES; do
                            ALIAS=$(basename "$CERT" | cut -d. -f1)
                            
                            # Check if alias exists in JKS
                            keytool -list -keystore "$TRUSTSTORE" -storepass "$TRUSTSTORE_PASS" -alias "$ALIAS" > /dev/null 2>&1
                            
                            if [ $? -ne 0 ]; then
                                echo "--- Found New Certificate: $ALIAS ---"
                                ./scripts/import-cert.sh "$CERT" "$TRUSTSTORE" "$TRUSTSTORE_PASS" "$ALIAS"
                                if [ $? -eq 0 ]; then
                                    IMPORT_STATUS=1
                                fi
                            else
                                echo "Certificate $ALIAS already exists. Skipping."
                            fi
                        done

                        # Exit with code 100 if we actually imported something
                        if [ $IMPORT_STATUS -eq 1 ]; then
                            exit 100
                        else
                            exit 0
                        fi
                        ''',
                        returnStatus: true
                    )

                    // Update the environment variable based on the Exit Code
                    if (statusCode == 100) {
                        env.CERT_IMPORTED = "true"
                        echo "STATUS: New certificates were imported. Deployment will proceed."
                    } else {
                        env.CERT_IMPORTED = "false"
                        echo "STATUS: No new certificates found. Deployment will be skipped."
                    }
                }
            }
        }

        stage('Verify Truststore Content') {
            when { expression { env.CERT_IMPORTED == 'true' } }
            steps {
                sh "keytool -list -keystore ${TRUSTSTORE} -storepass ${TRUSTSTORE_PASS} | grep 'trustedCertEntry' | tail -n 5"
            }
        }

        stage('Sync Truststore to Project Directory') {
            when { expression { env.CERT_IMPORTED == 'true' } }
            steps {
                sh "cp ${TRUSTSTORE} helm/mi-deployment/conf/client-truststore.jks"
            }
        }

        stage('Update Kubernetes ConfigMap') {
            when { expression { env.CERT_IMPORTED == 'true' } }
            steps {
                sh "kubectl create configmap mi-truststore --from-file=${TRUSTSTORE} --dry-run=client -o yaml | kubectl apply -f -"
            }
        }

        stage('Deploy with Helm') {
            when { expression { env.CERT_IMPORTED == 'true' } }
            steps {
                dir('helm') {
                    sh "helm upgrade --install ${RELEASE_NAME} ./mi-deployment -n ${K8S_NAMESPACE}"
                }
            }
        }

        stage('Restart Deployment') {
            when { expression { env.CERT_IMPORTED == 'true' } }
            steps {
                sh "kubectl rollout restart deployment/${RELEASE_NAME} -n ${K8S_NAMESPACE}"
            }
        }

        stage('Verify Deployment') {
            when { expression { env.CERT_IMPORTED == 'true' } }
            steps {
                sh "kubectl rollout status deployment/${RELEASE_NAME} -n ${K8S_NAMESPACE} --timeout=90s"
            }
        }
    }

    post {
        success {
            script {
                if (env.CERT_IMPORTED == 'true') {
                    echo "Successfully imported certificates and redeployed the application."
                } else {
                    echo "No changes needed. Pipeline finished successfully."
                }
            }
        }
        failure {
            echo "Pipeline failed. Please check the logs above for errors."
        }
    }
}
