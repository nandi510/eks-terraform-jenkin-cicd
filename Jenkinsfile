// ─────────────────────────────────────────────────────────────────────────────
// Jenkinsfile — EKS Terraform Pipeline
// Jenkins EC2 instance must have an IAM Role attached with the required
// permissions. No AWS credentials stored in Jenkins — uses instance metadata.
// ─────────────────────────────────────────────────────────────────────────────

pipeline {
    agent any   // runs on the Jenkins EC2 instance itself

    // ── Configurable parameters ──────────────────────────────────────────────
    parameters {
        choice(
            name: 'TF_ACTION',
            choices: ['plan-apply', 'destroy'],
            description: 'Choose what to do: plan+apply or destroy'
        )
        string(
            name: 'TF_VAR_cluster_name',
            defaultValue: 'my-eks-cluster',
            description: 'Override cluster name (optional)'
        )
    }

    // ── Environment ──────────────────────────────────────────────────────────
    environment {
        TF_IN_AUTOMATION  = 'true'          // disables interactive prompts
        TF_INPUT          = '0'             // same as -input=false
        AWS_DEFAULT_REGION = 'us-east-1'    // ← change if needed
        PLAN_FILE         = 'tfplan.binary'
    }

    options {
        timestamps()
        ansiColor('xterm')         // coloured terraform output  (install AnsiColor plugin)
        timeout(time: 60, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    stages {

        // ── 1. Checkout ───────────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
                sh 'echo "Branch: ${GIT_BRANCH} | Commit: ${GIT_COMMIT}"'
            }
        }

        // ── 2. Terraform Init ─────────────────────────────────────────────────
        stage('Terraform Init') {
            steps {
                dir('eks-terraform') {          // folder inside your repo
                    sh '''
                        terraform version
                        terraform init \
                          -backend=true \
                          -reconfigure
                    '''
                }
            }
        }

        // ── 3. Terraform Validate ─────────────────────────────────────────────
        stage('Terraform Validate') {
            steps {
                dir('eks-terraform') {
                    sh 'terraform validate'
                }
            }
        }

        // ── 4. Terraform Plan ─────────────────────────────────────────────────
        stage('Terraform Plan') {
            steps {
                dir('eks-terraform') {
                    sh """
                        terraform plan \
                          -var-file=terraform.tfvars \
                          -var 'cluster_name=${params.TF_VAR_cluster_name}' \
                          -out=${PLAN_FILE} \
                          -detailed-exitcode || true
                    """
                    // Save human-readable plan for the approval step
                    sh "terraform show -no-color ${PLAN_FILE} > plan_output.txt"
                    // Archive plan so reviewers can download it from Jenkins
                    archiveArtifacts artifacts: 'plan_output.txt', fingerprint: true
                }
            }
        }

        // ── 5. Manual Approval (plan-apply path only) ─────────────────────────
        stage('Approval — Review Plan') {
            when {
                expression { params.TF_ACTION == 'plan-apply' }
            }
            steps {
                script {
                    // Print plan summary in console for quick review
                    sh 'cat eks-terraform/plan_output.txt'

                    // Gate — a human must click Proceed or Abort within 30 min
                    timeout(time: 30, unit: 'MINUTES') {
                        input(
                            id: 'terraform-apply-approval',
                            message: '📋 Review the Terraform plan above. Proceed with Apply?',
                            ok: 'Yes, Apply!',
                            submitter: '',    // leave empty = any user can approve
                                              // or set to 'admin,devops-team'
                            parameters: [
                                booleanParam(
                                    name: 'CONFIRM',
                                    defaultValue: false,
                                    description: 'Check this box to confirm you reviewed the plan'
                                )
                            ]
                        )
                    }
                }
            }
        }

        // ── 6. Terraform Apply ────────────────────────────────────────────────
        stage('Terraform Apply') {
            when {
                expression { params.TF_ACTION == 'plan-apply' }
            }
            steps {
                dir('eks-terraform') {
                    sh "terraform apply -auto-approve ${PLAN_FILE}"
                }
            }
        }

        // ── 7. Manual Approval — Destroy (destroy path only) ──────────────────
        stage('Approval — Confirm Destroy') {
            when {
                expression { params.TF_ACTION == 'destroy' }
            }
            steps {
                script {
                    timeout(time: 10, unit: 'MINUTES') {
                        input(
                            id: 'terraform-destroy-approval',
                            message: '⚠️  DESTRUCTIVE: This will DELETE the EKS cluster and ALL resources. Are you sure?',
                            ok: 'Yes, DESTROY',
                            submitter: 'admin'   // ← restrict destroy to admin only
                        )
                    }
                }
            }
        }

        // ── 8. Terraform Destroy ──────────────────────────────────────────────
        stage('Terraform Destroy') {
            when {
                expression { params.TF_ACTION == 'destroy' }
            }
            steps {
                dir('eks-terraform') {
                    sh '''
                        terraform destroy \
                          -var-file=terraform.tfvars \
                          -auto-approve
                    '''
                }
            }
        }
    }

    // ── Post actions ──────────────────────────────────────────────────────────
    post {
        always {
            dir('eks-terraform') {
                // Clean up the binary plan file (contains secrets, don't archive)
                sh "rm -f ${PLAN_FILE}"
            }
        }
        success {
            echo '✅ Pipeline completed successfully.'
        }
        failure {
            echo '❌ Pipeline failed. Check the logs above.'
        }
        aborted {
            echo '⏹️  Pipeline was aborted (manual approval declined or timed out).'
        }
    }
}
