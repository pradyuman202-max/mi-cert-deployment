def CERT_IMPORTED = "false"

pipeline {
    agent any

    environment {
        TRUSTSTORE = "client-truststore.jks"
        TRUSTSTORE_PASS = "wso2carbon"
        K8S_NAMESPACE = "default" 
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
                        FILES=$(find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\))
                        
                        if [ -z "$FILES" ]; then
                            exit 0
                        fi

                        chmod +x scripts/import-cert.sh

                        for CERT in $FILES; do
                            ALIAS=$(basename "$CERT" | cut -d. -f1)
                            keytool -list -keystore "$TRUSTSTORE" -storepass "$TRUSTSTORE_PASS" -alias "$ALIAS" > /dev/null 2>&1
                            
                            if [ $? -ne 0 ]; then
                                ./scripts/import-cert.sh "$CERT" "$TRUSTSTORE" "$TRUSTSTORE_PASS" "$ALIAS"
                                if [ $? -eq 0 ]; then IMPORT_STATUS=1; fi
                            fi
                        done

                        if [ $IMPORT_STATUS -eq 1 ]; then exit 100; else exit 0; fi
                        ''',
                        returnStatus: true
                    )

                    if (statusCode == 100) {
                        CERT_IMPORTED = "true"
                    } else {
                        CERT_IMPORTED = "false"
                    }
                }
            }
        }

        stage('Update Kubernetes ConfigMap') {
            when { expression { return CERT_IMPORTED == 'true' } }
            steps {
                sh "kubectl create configmap mi-truststore --from-file=${TRUSTSTORE} --dry-run=client -o yaml | kubectl apply -f -"
            }
        }

        stage('Cleanup Existing Service') {
            when { expression { return CERT_IMPORTED == 'true' } }
            steps {
                script {
                    // This removes the service if it exists to free up port 30290
                    sh "kubectl delete service mi-service -n ${K8S_NAMESPACE} --ignore-not-found=true"
                }
            }
        }

        stage('Deploy with Helm') {
            when { expression { return CERT_IMPORTED == 'true' } }
            steps {
                sh '''
                echo "Deploying Micro Integrator with Helm..."
                # Copy truststore to where the chart expects it (based on your folder structure)
                mkdir -p helm/conf/
                cp ${TRUSTSTORE} helm/conf/client-truststore.jks
                
                helm upgrade --install ${RELEASE_NAME} ./helm \
                -f values.yaml \
                -n ${K8S_NAMESPACE}
                '''
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
                    echo "Successfully redeployed with new certificates."
                }
            }
        }
    }
}
