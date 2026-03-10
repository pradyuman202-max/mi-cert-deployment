pipeline {
    agent any
    
    environment {
        TRUSTSTORE = "client-truststore.jks"
        TRUSTSTORE_PASS = "wso2carbon"
        PROJECT_PATH = "/home/svc_account_wso2/SIT_MI_Docker_Project"
        K8S_NAMESPACE = "mi"
        CONFIGMAP_NAME = "mi-truststore-config"
        CERT_IMPORTED = "false"  // Initialize as false
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
                        script: '''#!/bin/bash
                        set +e
                        
                        echo "Searching for certificates..."
                        
                        # Find certificate files
                        CERT_FILES=$(find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\))
                        
                        if [ -z "$CERT_FILES" ]; then
                            echo "No certificate files found in repository."
                            echo "RESULT:false"
                            exit 0
                        fi
                        
                        chmod +x scripts/import-cert.sh
                        
                        # Create truststore if missing
                        if [ ! -f "$TRUSTSTORE" ]; then
                            echo "Truststore not found. Creating new truststore..."
                            keytool -genkeypair \\
                                -alias temp \\
                                -keystore $TRUSTSTORE \\
                                -storepass $TRUSTSTORE_PASS \\
                                -keypass $TRUSTSTORE_PASS \\
                                -dname "CN=temp" \\
                                -keyalg RSA \\
                                -validity 1
                            
                            keytool -delete -alias temp -keystore $TRUSTSTORE -storepass $TRUSTSTORE_PASS
                        fi
                        
                        # Track if any new certificates were imported
                        NEW_CERTS_IMPORTED=false
                        
                        for CERT in $CERT_FILES
                        do
                            CERT_NAME=$(basename "$CERT")
                            ALIAS=$(basename "$CERT" | cut -d. -f1)
                            
                            echo "Processing certificate: $CERT_NAME"
                            
                            # Check if certificate already exists in truststore
                            if keytool -list -keystore $TRUSTSTORE -storepass $TRUSTSTORE_PASS -alias "$ALIAS" > /dev/null 2>&1; then
                                echo "Certificate $ALIAS already exists in truststore. Skipping."
                            else
                                echo "Importing NEW certificate: $ALIAS"
                                ./scripts/import-cert.sh "$CERT" "$TRUSTSTORE" "$TRUSTSTORE_PASS" "$ALIAS"
                                if [ $? -eq 0 ]; then
                                    NEW_CERTS_IMPORTED=true
                                    echo "Successfully imported: $ALIAS"
                                else
                                    echo "Failed to import: $ALIAS"
                                fi
                            fi
                        done
                        
                        # Output result marker for parsing
                        echo "RESULT:$NEW_CERTS_IMPORTED"
                        ''',
                        returnStdout: true
                    ).trim()
                    
                    // Parse the result to get only the boolean value
                    def importStatus = result.split('\n').findAll { it.startsWith('RESULT:') }
                    if (importStatus) {
                        env.CERT_IMPORTED = importStatus.last().replace('RESULT:', '')
			env.CERT_IMPORTED = 'true'
                    } else {
                        env.CERT_IMPORTED = 'false'
                    }
                    
                    echo "New certificates imported: ${env.CERT_IMPORTED}"
                }
            }
        }
        
        stage('Organize Certificates') {
            when {
                expression { env.CERT_IMPORTED == 'true' }
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
                ls -l $CERT_DEST || echo "No certificates directory found"
                '''
            }
        }
        
        stage('Verify Truststore Content') {
            when {
                expression { env.CERT_IMPORTED == 'true' }
            }
            steps {
                sh '''
                echo "Listing truststore contents:"
                keytool -list -keystore $TRUSTSTORE -storepass $TRUSTSTORE_PASS | grep -E "Entry|Alias"
                '''
            }
        }
        
        stage('Sync Truststore to Project Directory') {
            when {
                expression { env.CERT_IMPORTED == 'true' }
            }
            steps {
                sh '''
                echo "Copying updated truststore to project directory..."
                
                sudo cp -f $TRUSTSTORE $PROJECT_PATH/
                
                echo "Verifying copied truststore exists:"
                ls -l $PROJECT_PATH/$TRUSTSTORE
                '''
            }
        }
        
        stage('Update Kubernetes ConfigMap') {
            when {
                expression { env.CERT_IMPORTED == 'true' }
            }
            steps {
                sh '''
                echo "Updating Kubernetes ConfigMap..."
                
                kubectl delete configmap $CONFIGMAP_NAME -n $K8S_NAMESPACE --ignore-not-found=true
                
                kubectl create configmap $CONFIGMAP_NAME \\
                    --from-file=$PROJECT_PATH/$TRUSTSTORE \\
                    -n $K8S_NAMESPACE
                
                echo "ConfigMap created successfully"
                '''
            }
        }
        
        stage('Deploy with Helm') {
            when {
                expression { env.CERT_IMPORTED == 'true' }
            }
            steps {
                sh '''
                echo "Deploying Micro Integrator with Helm..."
                
                helm upgrade --install mi ./helm \\
                    -f values.yaml \\
                    -n $K8S_NAMESPACE \\
                    --wait \\
                    --timeout 5m
                '''
            }
        }
        
        stage('Restart Deployment') {
            when {
                expression { env.CERT_IMPORTED == 'true' }
            }
            steps {
                sh '''
                echo "Restarting MI deployment..."
                
                kubectl rollout restart deployment mi-deployment -n $K8S_NAMESPACE
                kubectl rollout status deployment mi-deployment -n $K8S_NAMESPACE --timeout=5m
                '''
            }
        }
        
        stage('Verify Deployment') {
            when {
                expression { env.CERT_IMPORTED == 'true' }
            }
            steps {
                sh '''
                echo "Checking pods..."
                kubectl get pods -n $K8S_NAMESPACE -l app=mi
                
                echo "Checking configmap..."
                kubectl get configmap $CONFIGMAP_NAME -n $K8S_NAMESPACE
                '''
            }
        }
    }
    
    post {
        success {
            script {
                if (env.CERT_IMPORTED == 'true') {
                    echo "✓ New certificates were imported. Truststore updated and deployment completed."
                } else {
                    echo "✓ No new certificates found. Deployment skipped as intended."
                }
            }
        }
        
        failure {
            echo '✗ Pipeline failed! Check the logs for details.'
        }
        
        always {
            cleanWs()  // Clean workspace after pipeline execution
        }
    }
}

