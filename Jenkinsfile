pipeline {
    agent any

    environment {
        IMAGE_NAME = "mi-local-image"
        IMAGE_TAG  = "wso2mi_410_sit0001"
        NAMESPACE  = "mi"
        HELM_CHART_PATH = "helm/"
        VALUES_FILE = "values.yaml"
    }

    stages {
        stage('Checkout Code') {
            steps {
                git branch: 'main',
                    credentialsId: 'github-ssh-key',
                    url: 'git@github.com:pradyuman202-max/mi-cert-deployment.git'
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    sh """
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                    """
                }
            }
        }

        stage('Push Docker Image (Optional)') {
            steps {
                script {
                    // If you have private registry
                    // sh "docker tag ${IMAGE_NAME}:${IMAGE_TAG} myregistry.com/${IMAGE_NAME}:${IMAGE_TAG}"
                    // sh "docker push myregistry.com/${IMAGE_NAME}:${IMAGE_TAG}"
                    echo "Skipping push for local testing"
                }
            }
        }

        stage('Deploy to Kubernetes with Helm') {
            steps {
                script {
                    sh """
                    helm upgrade --install mi ${HELM_CHART_PATH} -n ${NAMESPACE} -f ${VALUES_FILE}
                    """
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {
                    sh "kubectl get pods -n ${NAMESPACE}"
                }
            }
        }
    }

    post {
        success {
            echo "Deployment Successful!"
        }
        failure {
            echo "Deployment Failed! Check logs."
        }
    }
}
