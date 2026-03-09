// 1. THIS IS THE KEY FIX: Declare it here so it can be changed dynamically
def CERT_IMPORTED = "false"

pipeline {
    agent any

    environment {
        // Configuration
        TRUSTSTORE = "client-truststore.jks"
        TRUSTSTORE_PASS = "wso2carbon"
        K8S_NAMESPACE = "default" 
        RELEASE_NAME = "mi-deployment"
        // 2. REMOVED CERT_IMPORTED FROM HERE
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
                    def statusCode = sh(
                        script: '''
                        set +e
                        IMPORT_STATUS=0
                        echo "Searching for new certificates..."
                        
                        FILES=$(find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\))
                        
                        if [ -z "$FILES" ]; then
                            echo "No certificate files found in root."
                            exit 0
                        fi

                        chmod +x scripts/import-cert.sh

                        for CERT in $FILES; do
                            ALIAS=$(basename "$CERT" | cut -d. -f1)
                            
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

                        if [ $IMPORT_STATUS -eq 1 ]; then
                            exit 100
                        else
                            exit 0
                        fi
                        ''',
                        returnStatus: true
                    )

                    // 3. Update the variable without the "env." prefix
                    if (statusCode == 100) {
                        CERT_IMPORTED = "true"
                        echo "STATUS: New certificates were imported. Deployment will proceed."
                    } else {
                        CERT_IMPORTED = "false"
                        echo "STATUS: No new certificates found."
                    }
                }
            }
        }

        stage('Verify Truststore Content') {
            when { expression { return CERT_IMPORTED == 'true' } }
            steps {
                sh "keytool -list -keystore ${TRUSTSTORE} -storepass ${TRUSTSTORE_PASS} | grep 'trustedCertEntry' | tail -n 10"
            }
        }

        stage('Sync Truststore to Project Directory') {
            when { expression { return CERT_IMPORTED == 'true' } }
            steps {
                sh "mkdir -p helm/mi-deployment/conf/"
                sh "cp ${TRUSTSTORE} helm/mi-deployment/conf/client-truststore.jks"
            }
        }

        stage('Update Kubernetes ConfigMap') {
            when { expression { return CERT_IMPORTED == 'true' } }
            steps {
                sh "kubectl create configmap mi-truststore --from-file=${TRUSTSTORE} --dry-run=client -o yaml | kubectl apply -f -"
            }
        }

        stage('Deploy with Helm') {
            when { expression { return CERT_IMPORTED == 'true' } }
            steps {
                dir('helm') {
                    sh "echo "Deploying Micro Integrator with Helm..."
				helm upgrade --install mi ./helm \
				-f values.yaml \
				-n $K8S_NAMESPACE"
                }
            }
        }

        stage('Restart Deployment') {
            when { expression { return CERT_IMPORTED == 'true' } }
            steps {
                sh "kubectl rollout restart deployment/${RELEASE_NAME} -n ${K8S_NAMESPACE}"
            }
        }

        stage('Verify Deployment') {
            when { expression { return CERT_IMPORTED == 'true' } }
            steps {
                sh "kubectl rollout status deployment/${RELEASE_NAME} -n ${K8S_NAMESPACE} --timeout=90s"
            }
        }
    }

    post {
        success {
            script {
                if (CERT_IMPORTED == 'true') {
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
