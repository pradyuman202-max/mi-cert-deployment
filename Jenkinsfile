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

    stage('Check and Import Certificate') {
        steps {
            script {

                def certCheck = sh(
                    script: '''
                    chmod +x scripts/this_cert_check.sh
                    scripts/this_cert_check.sh
                    ''',
                    returnStatus: true
                )

                if (certCheck != 0) {
                    echo "No certificate detected. Skipping remaining stages."
                    return
                }

                echo "Certificate detected. Starting import."

                sh '''
                CERT_DIR="/home/svc_account_wso2/SIT_MI_Docker_Project"

                CERT_FILES=$(find "$CERT_DIR" -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\))

                chmod +x scripts/import-cert.sh

                if [ ! -f "$TRUSTSTORE" ]; then
                    echo "Truststore not found. Creating..."

                    keytool -genkeypair \
                    -alias temp \
                    -keystore $TRUSTSTORE \
                    -storepass $TRUSTSTORE_PASS \
                    -keypass $TRUSTSTORE_PASS \
                    -dname "CN=temp" \
                    -keyalg RSA

                    keytool -delete -alias temp -keystore $TRUSTSTORE -storepass $TRUSTSTORE_PASS
                fi

                for CERT in $CERT_FILES
                do
                    CERT_NAME=$(basename $CERT)
                    ALIAS=$(basename $CERT | cut -d. -f1)

                    echo "Importing certificate: $CERT_NAME"

                    ./scripts/import-cert.sh $CERT $TRUSTSTORE $TRUSTSTORE_PASS $ALIAS
                done
                '''
            }
        }
    }

    stage('Organize Certificates') {
        steps {
            script {

                def certCheck = sh(
                    script: 'scripts/this_cert_check.sh',
                    returnStatus: true
                )

                if (certCheck != 0) {
                    echo "No certificate detected. Skipping stage."
                    return
                }

                sh '''
                echo "Organizing certificates..."

                CERT_DEST="$PROJECT_PATH/certificates"
                mkdir -p $CERT_DEST

                find $PROJECT_PATH -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\) -exec mv -f {} $CERT_DEST/ \\;

                ls -l $CERT_DEST
                '''
            }
        }
    }

    stage('Verify Truststore Content') {
        steps {
            script {

                def certCheck = sh(
                    script: 'scripts/this_cert_check.sh',
                    returnStatus: true
                )

                if (certCheck != 0) {
                    echo "No certificate detected. Skipping stage."
                    return
                }

                sh '''
                echo "Listing truststore contents:"
                keytool -list -keystore $TRUSTSTORE -storepass $TRUSTSTORE_PASS
                '''
            }
        }
    }

    stage('Sync Truststore to Project Directory') {
        steps {
            script {

                def certCheck = sh(
                    script: 'scripts/this_cert_check.sh',
                    returnStatus: true
                )

                if (certCheck != 0) {
                    echo "No certificate detected. Skipping stage."
                    return
                }

                sh '''
                echo "Copying truststore to project directory..."

                sudo cp $TRUSTSTORE $PROJECT_PATH/

                keytool -list -keystore $PROJECT_PATH/$TRUSTSTORE -storepass $TRUSTSTORE_PASS
                '''
            }
        }
    }

    stage('Update Kubernetes ConfigMap') {
        steps {
            script {

                def certCheck = sh(
                    script: 'scripts/this_cert_check.sh',
                    returnStatus: true
                )

                if (certCheck != 0) {
                    echo "No certificate detected. Skipping stage."
                    return
                }

                sh '''
                echo "Updating Kubernetes ConfigMap..."

                kubectl delete configmap $CONFIGMAP_NAME -n $K8S_NAMESPACE --ignore-not-found

                kubectl create configmap $CONFIGMAP_NAME \
                --from-file=$PROJECT_PATH/$TRUSTSTORE \
                -n $K8S_NAMESPACE
                '''
            }
        }
    }

    stage('Deploy with Helm') {
        steps {
            script {

                def certCheck = sh(
                    script: 'scripts/this_cert_check.sh',
                    returnStatus: true
                )

                if (certCheck != 0) {
                    echo "No certificate detected. Skipping stage."
                    return
                }

                sh '''
                echo "Deploying Micro Integrator with Helm..."

                helm upgrade --install mi ./helm \
                -f values.yaml \
                -n $K8S_NAMESPACE
                '''
            }
        }
    }

    stage('Restart Deployment') {
        steps {
            script {

                def certCheck = sh(
                    script: 'scripts/this_cert_check.sh',
                    returnStatus: true
                )

                if (certCheck != 0) {
                    echo "No certificate detected. Skipping stage."
                    return
                }

                sh '''
                echo "Restarting MI deployment..."

                kubectl rollout restart deployment mi-deployment -n $K8S_NAMESPACE
                kubectl rollout status deployment mi-deployment -n $K8S_NAMESPACE
                '''
            }
        }
    }

    stage('Verify Deployment') {
        steps {
            script {

                def certCheck = sh(
                    script: 'scripts/this_cert_check.sh',
                    returnStatus: true
                )

                if (certCheck != 0) {
                    echo "No certificate detected. Skipping stage."
                    return
                }

                sh '''
                echo "Checking pods..."
                kubectl get pods -n $K8S_NAMESPACE

                echo "Checking configmap..."
                kubectl describe configmap $CONFIGMAP_NAME -n $K8S_NAMESPACE
                '''
            }
        }
    }

}

post {
    success {
        echo "Pipeline completed."
    }

    failure {
        echo "Pipeline failed!"
    }
