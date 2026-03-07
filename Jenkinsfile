pipeline {
    agent any

    environment {
        NAMESPACE = "mi"
        CONFIGMAP_NAME = "mi-truststore-config"
        TRUSTSTORE = "client-truststore.jks"
        PASSWORD = "wso2carbon"
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
                sh '''
                echo "Searching for certificates..."

                CERT_FILES=$(find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\))

                if [ -z "$CERT_FILES" ]; then
                    echo "No certificates found in repository."
                    exit 0
                fi

                chmod +x scripts/import-cert.sh

                for cert in $CERT_FILES
                do
                    CERT_NAME=$(basename $cert)
                    ALIAS=$(basename $cert | cut -d'.' -f1)

                    echo "-------------------------------------"
                    echo "Processing certificate: $CERT_NAME"
                    echo "Alias: $ALIAS"
                    echo "-------------------------------------"

                    ./scripts/import-cert.sh "$cert" "$TRUSTSTORE" "$PASSWORD" "$ALIAS"
                done
                '''
            }
        }

        stage('Update Kubernetes ConfigMap') {
            steps {
                sh '''
                echo "Updating Kubernetes ConfigMap..."

                kubectl delete configmap $CONFIGMAP_NAME -n $NAMESPACE --ignore-not-found

                kubectl create configmap $CONFIGMAP_NAME \
                --from-file=$TRUSTSTORE \
                -n $NAMESPACE
                '''
            }
        }

        stage('Deploy with Helm') {
            steps {
                sh '''
                echo "Deploying with Helm..."

                helm upgrade --install mi helm/mi \
                -f values.yaml \
                -n $NAMESPACE
                '''
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                echo "Pods status:"
                kubectl get pods -n $NAMESPACE

                echo "ConfigMap:"
                kubectl describe configmap $CONFIGMAP_NAME -n $NAMESPACE
                '''
            }
        }
    }

    post {
        success {
            echo "Pipeline completed successfully!"
        }
        failure {
            echo "Pipeline failed. Check logs."
        }
    }
}
