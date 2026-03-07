pipeline {
    agent any

    environment {
        TRUSTSTORE = "client-truststore.jks"
        TRUSTSTORE_PASS = "wso2carbon"
        PROJECT_PATH = "/home/svc_account_wso2/SIT_MI_Docker_Project"
        K8S_NAMESPACE = "mi"
        CONFIGMAP_NAME = "mi-truststore-config"
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

        stage('Auto Import Certificates (Only New Ones)') {
            steps {
                sh '''
                echo "Searching for certificates..."

                CERT_FILES=$(find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\))

                if [ -z "$CERT_FILES" ]; then
                    echo "No certificates found"
                    exit 0
                fi

                chmod +x scripts/import-cert.sh

                for CERT in $CERT_FILES
                do
                    CERT_NAME=$(basename $CERT)
                    ALIAS=$(basename $CERT | cut -d. -f1)

                    echo "-------------------------------------"
                    echo "Processing certificate: $CERT_NAME"
                    echo "Alias: $ALIAS"
                    echo "-------------------------------------"

                    # Check if alias already exists in truststore
                    keytool -list -keystore $TRUSTSTORE -storepass $TRUSTSTORE_PASS -alias $ALIAS > /dev/null 2>&1

                    if [ $? -eq 0 ]; then
                        echo "Certificate with alias $ALIAS already exists in truststore. Skipping import."
                    else
                        echo "New certificate detected. Importing..."
                        ./scripts/import-cert.sh $CERT $TRUSTSTORE $TRUSTSTORE_PASS $ALIAS
                    fi
                done
                '''
            }
        }

        stage('Verify Truststore Content') {
            steps {
                sh '''
                echo "Listing truststore contents:"
                keytool -list -keystore $TRUSTSTORE -storepass $TRUSTSTORE_PASS
                '''
            }
        }

        stage('Sync Truststore to Project Directory') {
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
            steps {
                sh '''
                echo "Deploying Micro Integrator with Helm..."

                helm upgrade --install mi ./helm/ \
                -f values.yaml \
                -n $K8S_NAMESPACE
                '''
            }
        }

        stage('Restart Deployment') {
            steps {
                sh '''
                echo "Restarting MI deployment to load new truststore..."

                kubectl rollout restart deployment mi-deployment -n $K8S_NAMESPACE
                kubectl rollout status deployment mi-deployment -n $K8S_NAMESPACE
                '''
            }
        }

        stage('Verify Deployment') {
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
            echo 'Pipeline completed successfully!'
        }
        failure {
            echo 'Pipeline failed!'
        }
    }
}
