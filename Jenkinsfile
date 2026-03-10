pipeline {
agent any

environment {
    TRUSTSTORE = "client-truststore.jks"
    TRUSTSTORE_PASS = "wso2carbon"
    PROJECT_PATH = "/home/svc_account_wso2/SIT_MI_Docker_Project"
    K8S_NAMESPACE = "mi"
    CONFIGMAP_NAME = "mi-truststore-config"
    CERT_IMPORTED = "true"
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

    def result = sh(
        script: '''
        set +e
        CERT_IMPORTED=false

        echo "Checking latest git commit for new certificate files..."

        NEW_CERT_FILES=$(git diff-tree --no-commit-id --name-only -r HEAD | grep -E '\\.(crt|cer)$')

        if [ -z "$NEW_CERT_FILES" ]; then
            echo "No new certificate files detected."
            echo "false"
            exit 0
        fi

        echo "New certificate files detected:"
        echo "$NEW_CERT_FILES"

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

            keytool -delete -alias temp \
            -keystore $TRUSTSTORE \
            -storepass $TRUSTSTORE_PASS
        fi

        for CERT in $NEW_CERT_FILES
        do
            CERT_NAME=$(basename $CERT)
            ALIAS=$(basename $CERT | cut -d. -f1)

            echo "Processing certificate: $CERT_NAME"

            keytool -list -keystore $TRUSTSTORE -storepass $TRUSTSTORE_PASS -alias $ALIAS > /dev/null 2>&1

            if [ $? -eq 0 ]; then
                echo "Certificate $ALIAS already exists in truststore."
            else
                echo "Importing new certificate $ALIAS"
                ./scripts/import-cert.sh $CERT $TRUSTSTORE $TRUSTSTORE_PASS $ALIAS
                CERT_IMPORTED=true
            fi
        done

        echo $CERT_IMPORTED
        ''',
        returnStdout: true
    ).trim()

    env.CERT_IMPORTED = result

    echo "New certificate imported: ${env.CERT_IMPORTED}"
		}
        }
    }

	stage('Organize Certificates') {
    when {
        expression { env.CERT_IMPORTED == "true" }
    }
    steps {
        sh '''
        echo "Organizing certificates into central directory..."

        CERT_DEST="/home/svc_account_wso2/SIT_MI_Docker_Project/certificates"
        PROJECT_DIR="/home/svc_account_wso2/SIT_MI_Docker_Project"

        mkdir -p $CERT_DEST

        echo "Moving all certificate files from project root..."

        find $PROJECT_DIR -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\) -exec mv -f {} $CERT_DEST/ \\;

        echo "Current certificate directory content:"
        ls -l $CERT_DEST

        echo "Checking project root for remaining certificates..."
        find $PROJECT_DIR -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\)
        '''
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
