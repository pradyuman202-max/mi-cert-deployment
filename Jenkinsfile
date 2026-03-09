pipeline {
    agent any

    environment {
        TRUSTSTORE = "client-truststore.jks"
        TRUSTSTORE_PASS = "wso2carbon"
        PROJECT_PATH = "/home/svc_account_wso2/SIT_MI_Docker_Project"
        K8S_NAMESPACE = "mi"
        CONFIGMAP_NAME = "mi-truststore-config"
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

        stage('Verify Repo Files') {
            steps {
                sh '''
                echo "Repository files:"
                ls -l
                '''
            }
        }

        stage('Auto Import Certificates') {
            steps {
                script {
                    sh '''
                    set +e
                    
                    # Initialize our status text file as false
                    echo "false" > cert_status.txt

                    echo "Searching for certificates..."
                    CERT_FILES=$(find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\))

                    if [ -z "$CERT_FILES" ]; then
                        echo "No certificate files found."
                        exit 0
                    fi

                    chmod +x scripts/import-cert.sh

                    # Create truststore if missing
                    if [ ! -f "$TRUSTSTORE" ]; then
                        echo "Truststore not found. Creating new truststore..."
                        keytool -genkeypair \
                        -alias temp \
                        -keystore $TRUSTSTORE \
                        -storepass $TRUSTSTORE_PASS \
                        -keypass $TRUSTSTORE_PASS \
                        -dname "CN=temp" \
                        -keyalg RSA

                        keytool -delete -alias temp -keystore $TRUSTSTORE -storepass $TRUSTSTORE_PASS
                    fi

                    # Loop through certificates
                    for CERT in $CERT_FILES
                    do
                        CERT_NAME=$(basename $CERT)
                        ALIAS=$(basename $CERT | cut -d. -f1)

                        echo "Processing certificate: $CERT_NAME"
                        
                        # Capture the output of the script into a variable
                        OUTPUT=$(./scripts/import-cert.sh "$CERT" "$TRUSTSTORE" "$TRUSTSTORE_PASS" "$ALIAS" 2>&1)
                        
                        # Print the output to the Jenkins console
                        echo "$OUTPUT"
                        
                        # If the output contains our success message, write true to our text file
                        if echo "$OUTPUT" | grep -q "Certificate imported successfully"; then
                            echo "true" > cert_status.txt
                        fi
                    done
                    '''

                    // Securely read the text file directly into our environment variable
                    env.CERT_IMPORTED = readFile('cert_status.txt').trim()

                    echo "New certificate imported: ${env.CERT_IMPORTED}"
                }
            }
        }

        stage('Verify Truststore Content') {
            when {
                expression { env.CERT_IMPORTED == "true" }
            }
            steps {
                sh '''
                echo "Listing truststore contents:"
                keytool -list -keystore $TRUSTSTORE -storepass $TRUSTSTORE_PASS
                '''
            }
        }

        stage('Sync Truststore to Project Directory') {
            when {
                expression { env.CERT_IMPORTED == "true" }
            }
            steps {
                sh '''
                echo "Copying updated truststore to project directory..."

                sudo cp $TRUSTSTORE $PROJECT_PATH/

                echo "Verifying copied truststore:"
                keytool -list -keystore $PROJECT_PATH/$TRUSTSTORE -storepass $TRUSTSTORE_PASS
                '''
            }
        }

        stage('Update Kubernetes ConfigMap') {
            when {
                expression { env.CERT_IMPORTED == "true" }
            }
            steps {
                sh '''
                echo "Updating Kubernetes ConfigMap..."

                kubectl delete configmap $CONFIGMAP_NAME -n $K8S_NAMESPACE --ignore-not-found

                kubectl create configmap $CONFIGMAP_NAME \
                --from-file=$PROJECT_PATH/$TRUSTSTORE \
                -n $K8S_NAMESPACE
                '''
            }
        }

        stage('Deploy with Helm') {
            when {
                expression { env.CERT_IMPORTED == "true" }
            }
            steps {
                sh '''
                echo "Deploying Micro Integrator with Helm..."

                helm upgrade --install mi ./helm \
                -f values.yaml \
                -n $K8S_NAMESPACE
                '''
            }
        }

        stage('Restart Deployment') {
            when {
                expression { env.CERT_IMPORTED == "true" }
            }
            steps {
                sh '''
                echo "Restarting MI deployment..."

                kubectl rollout restart deployment mi-deployment -n $K8S_NAMESPACE
                kubectl rollout status deployment mi-deployment -n $K8S_NAMESPACE
                '''
            }
        }

        stage('Verify Deployment') {
            when {
                expression { env.CERT_IMPORTED == "true" }
            }
            steps {
                sh '''
                echo "Checking pods..."
                kubectl get pods -n $K8S_NAMESPACE

                echo "Checking configmap..."
                kubectl describe configmap $CONFIGMAP_NAME -n $K8S_NAMESPACE
                '''
            }
        }
    }

    post {
        success {
            script {
                if (env.CERT_IMPORTED == "true") {
                    echo "New certificate detected. Truststore updated and deployment completed."
                } else {
                    echo "No new certificates found. Deployment skipped."
                }
            }
        }

        failure {
            echo 'Pipeline failed!'
        }
    }
}
