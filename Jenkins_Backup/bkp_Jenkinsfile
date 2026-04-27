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
                    echo "No certificate detected. Skipping import."
                    return
                }

                echo "Certificate detected. Starting import."

                sh '''
                CERT_DIR="/home/svc_account_wso2/SIT_MI_Docker_Project"

                CERT_FILES=$(find "$CERT_DIR" -type f \\( -name "*.crt" -o -name "*.cer" \\))

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

}
}
