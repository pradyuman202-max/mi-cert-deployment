	def CERT_IMPORTED = "false"

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
						def statusCode = sh(
							script: '''
							set +e
							IMPORT_STATUS=0
							echo "Searching for new certificates..."

							FILES=$(find . -maxdepth 1 -type f \\( -name "*.crt" -o -name "*.cer" \\))

							if [ -z "$FILES" ]; then
								echo "No certificate files found in root."
								exit 0
							fi

							chmod +x scripts/import-cert.sh

							for CERT in $FILES; do
								ALIAS=$(basename "$CERT" | cut -d. -f1)

								keytool -list -keystore "$TRUSTSTORE" -storepass "$TRUSTSTORE_PASS" -alias "$ALIAS" > /dev/null 2>&1

								if [ $? -ne 0 ]; then
									echo "--- Found New Certificate: $ALIAS ---"
									./scripts/import-cert.sh "$CERT" "$TRUSTSTORE" "$TRUSTSTORE_PASS" "$ALIAS"
									if [ $? -eq 0 ]; then
										IMPORT_STATUS=1
									fi
								else
									echo "Certificate $ALIAS already exists. Skipping."
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

						// 3. Update the variable without the "env." prefix
						if (statusCode == 100) {
							CERT_IMPORTED = "true"
							echo "STATUS: New certificates were imported. Deployment will proceed."
						} else {
							CERT_IMPORTED = "false"
							echo "STATUS: No new certificates found."
						}
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
