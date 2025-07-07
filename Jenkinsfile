def COLOR_MAP = [
    'SUCCESS': 'good', 
    'FAILURE': 'danger',
]

pipeline {
    agent { node { label 'TERRAFORM' } } 
    parameters {
                choice(name: 'Deployment_Type', choices:['apply','destroy'],description:'The deployment type')
                choice (name: 'Manual_Approval', choices: ['Approve','Reject'], description: 'Approve or Reject the deployment')
                  }
    environment {
        EMAIL_TO = 'betechincorporated@gmail.com'
    }
    stages {
        stage('1.Terraform init') {
            steps {
                echo 'terraform init phase'
                sh 'AWS_REGION=us-west-2 terraform init'
            }
        }
        stage('2.Terraform plan') {
            steps {
                echo 'terraform plan phase'
                sh 'AWS_REGION=us-west-2 terraform plan'
            }
        }

        stage('3.Manual Approval') {
            steps {
                script {
                    def Manual_Approval = 'Approve'  // Set to 'Approve' or 'Reject' as needed
                    echo "Deployment ${Manual_Approval}"

                    if (Manual_Approval == 'Reject') {
                        error "Deployment rejected, stopping pipeline."
                    } 
                }  
            }
        }

/*
        stage('3.Manual Approval') {
            input {
                message "Should we proceed?"
                ok "Yes, we should."
                parameters{
                    choice (name: 'Manual_Approval', choices: ['Approve','Reject'], description: 'Approve or Reject the deployment')
                }  
            }
             steps {
                echo "Deployment ${Manual_Approval}"
            }          
        }
*/
        stage('4.Terraform Deploy') {              
            steps { 
                echo 'Terraform ${params.Deployment_Type} phase'  
                sh "AWS_REGION=us-west-2 terraform ${params.Deployment_Type} --auto-approve"
                sh("""scripts/update-kubeconfig.sh""")
                sh("""scripts/install_helm.sh""") 
                }
                }
        stage ('5. Email Notification') {
            steps {
               echo 'Success 4 BETECH'
               mail bcc: 'betechincorporated@gmail.com', body: '''Terraform deployment is completed.
               Let me know if the changes look okay.
               Thanks,
               BETECH Solutions,
               +1 (123) 123-4567''', cc: 'betechincorporated@gmail.com', from: '', replyTo: '', subject: 'Terraform Infra deployment completed!!!', to: 'betechincorporated@gmail.com'
               }
          }
     }       
    post {
        success {
            // Triggering the weather-app-deployment build
            build job: 'weather-app-deployment'
        }
        failure {
            echo 'Build failed, not triggering deployment.'
        }
        always {
            echo 'Slack Notifications.'
            slackSend channel: '#all-weatherapp-cicd',
                color: COLOR_MAP[currentBuild.currentResult],
                message: "*${currentBuild.currentResult}:* Job ${env.JOB_NAME} build ${env.BUILD_NUMBER} \n More info at: ${env.BUILD_URL}"
        }
    }
} 
