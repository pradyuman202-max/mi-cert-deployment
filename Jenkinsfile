pipeline {
agent any

```
environment {
    TRUSTSTORE = "client-truststore.jks"
    TRUSTSTORE_PASS = "wso2carbon"
    CERT_FILE = "backend-cert.crt"
    CERT_ALIAS = "backend-cert"
    NAMESPACE = "mi"
}

stages {

    stage('Checkout Code') {
        steps {
            git credentialsId: 'github-ssh-key',
            url: 'git@github.com:pradyuman202-max/mi-cert-deployment.git'
        }
    }

    stage('Verify Files') {
        steps {
            sh '''
            echo "Checking repository files..."
            ls -l
            '''
        }
    }

    stage('Backup and Import Certificate') {
        steps {
            sh '''
            chmod +x scripts/import-cert.sh

            ./scripts/import-cert.sh \
            $CERT_FILE \
            $TRUSTSTORE \
            $TRUSTSTORE_PASS \
            $CERT_ALIAS
            '''
        }
    }

    stage('Update Kubernetes ConfigMap') {
        steps {
            sh '''
            echo "Updating Kubernetes ConfigMap..."

            kubectl create configmap mi-truststore-config \
            --from-file=$TRUSTSTORE \
            -n $NAMESPACE \
            --dry-run=client -o yaml | kubectl apply -f -
            '''
        }
    }

    stage('Deploy with Helm') {
        steps {
            sh '''
            echo "Deploying WSO2 MI..."

            helm upgrade --install mi helm/ -n $NAMESPACE -f values.yaml
            '''
        }
    }

    stage('Verify Deployment') {
        steps {
            sh '''
            echo "Checking rollout status..."

            kubectl rollout status deployment mi-deployment -n $NAMESPACE

            echo "Running pods:"
            kubectl get pods -n $NAMESPACE
            '''
        }
    }
}

post {
    success {
        echo "Deployment completed successfully."
    }
    failure {
        echo "Deployment failed."
    }
}
```

}

