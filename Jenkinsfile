def CERT_IMPORTED = "false"

pipeline {
    agent any

    environment {
        TRUSTSTORE = "client-truststore.jks"
        TRUSTSTORE_PASS = "wso2carbon"

        PROJECT_PATH = "/home/svc_account_wso2/SIT_MI_Docker_Project"

        K8S_NAMESPACE = "mi"
        RELEASE_NAME = "mi-deployment"
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

                        echo "Searching for certificates..."

                        FILES=$(find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\))

                        if [ -z "$FILES" ]; then
                            echo "No certificate files found"
                            exit 0
                        fi

                        chmod +x scripts/import-cert.sh

                        for CERT in $FILES
                        do
                            ALIAS=$(basename "$CERT" | cut -d. -f1)

                            keytool -list -keystore "$TRUSTSTORE" -storepass "$TRUSTSTORE_PASS" -alias "$ALIAS" > /dev/null 2>&1

                            if [ $? -ne 0 ]; then
                                echo "Importing certificate: $ALIAS"

                                ./scripts/import-cert.sh "$CERT" "$TRUSTSTORE" "$TRUSTSTORE_PASS" "$ALIAS"

                                if [ $? -eq 0 ]; then
                                    IMPORT_STATUS=1
                                fi
                            else
                                echo "Certificate $ALIAS already exists"
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
                        echo "New certificates imported."
                    } else {
                        CERT_IMPORTED = "false"
                        echo "No new certificates found."
                    }
                }
            }
        }

        stage('Verify Truststore') {
            when {
                expression { CERT_IMPORTED == "true" }
            }
            steps {
                sh """
                keytool -list -keystore ${TRUSTSTORE} -storepass ${TRUSTSTORE_PASS} | grep trustedCertEntry | tail
                """
            }
        }

        stage('Copy Truststore to Helm Project') {
            when {
                expression { CERT_IMPORTED == "true" }
            }
            steps {
                sh """
                cp ${TRUSTSTORE} ${PROJECT_PATH}/client-truststore.jks
                """
            }
        }

        stage('Update ConfigMap') {
            when {
                expression { CERT_IMPORTED == "true" }
            }
            steps {
                sh """
                kubectl create configmap mi-truststore \
                --from-file=${PROJECT_PATH}/client-truststore.jks \
                -n ${K8S_NAMESPACE} \
                --dry-run=client -o yaml | kubectl apply -f -
                """
            }
        }

        stage('Helm Upgrade Deployment') {
            when {
                expression { CERT_IMPORTED == "true" }
            }
            steps {
                sh """
                helm upgrade --install ${RELEASE_NAME} ${PROJECT_PATH}/helm -n ${K8S_NAMESPACE}
                """
            }
        }

        stage('Restart Deployment') {
            when {
                expression { CERT_IMPORTED == "true" }
            }
            steps {
                sh """
                kubectl rollout restart deployment/${RELEASE_NAME} -n ${K8S_NAMESPACE}
                """
            }
        }

        stage('Verify Deployment') {
            when {
                expression { CERT_IMPORTED == "true" }
            }
            steps {
                sh """
                kubectl rollout status deployment/${RELEASE_NAME} -n ${K8S_NAMESPACE} --timeout=120s

                kubectl get pods -n ${K8S_NAMESPACE}
                """
            }
        }
    }

    post {

        success {
            script {
                if (CERT_IMPORTED == "true") {
                    echo "Certificates imported and MI redeployed successfully."
                } else {
                    echo "No new certificates detected. Deployment skipped."
                }
            }
        }

        failure {
            echo "Pipeline failed."
        }
    }
}
