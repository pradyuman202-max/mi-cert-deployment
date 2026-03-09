def CERT_IMPORTED = "false"

pipeline {
    agent any

    environment {
        // Configuration
        TRUSTSTORE = "client-truststore.jks"
        TRUSTSTORE_PASS = "wso2carbon"
        K8S_NAMESPACE = "default" 
        // Using 'mi' as the release name based on your previous working command
        RELEASE_NAME = "mi"
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
                            echo "No certificate files found."
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

                    if (statusCode == 100) {
                        CERT_IMPORTED = "true"
                        echo "STATUS: New certificates detected. Deployment will proceed."
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
                // We copy it into the helm folder so the chart can package it
                sh "mkdir -p helm/conf/"
                sh "cp ${TRUSTSTORE} helm/conf/client-truststore.jks"
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
                // We run from the ROOT directory so we can find 'values.yaml' and the './helm' folder
                sh '''
                echo "Deploying Micro Integrator with Helm..."
                helm upgrade --install ${RELEASE_NAME} ./helm \
                -f values.yaml \
                -n ${K8S_NAMESPACE}
                '''
            }
        }

        stage('Restart Deployment') {
            when { expression { return CERT_IMPORTED == 'true' } }
            steps {
                // Using RELEASE_NAME variable for consistency
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
                    echo "Successfully updated certificates and redeployed."
                } else {
                    echo "No changes needed. Pipeline finished successfully."
                }
            }
        }
        failure {
            echo "Pipeline failed. Check Helm logs or Truststore paths."
        }
    }
}
